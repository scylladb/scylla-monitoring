package docker

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"os/exec"
	"strings"
	"time"
)

// ContainerConfig holds the configuration for starting a container.
type ContainerConfig struct {
	Name          string
	Image         string
	Cmd           []string
	Env           []string
	PortBindings  map[string]string // containerPort -> hostPort (e.g. "9090/tcp" -> "9090")
	Mounts        []MountConfig
	NetworkName   string
	ExtraHosts    []string
	RestartPolicy string // "", "unless-stopped", "always"
	ExtraArgs     []string
	HostNetwork   bool
	BindAddress   string
	User          string
}

// MountConfig describes a bind mount.
type MountConfig struct {
	Source   string
	Target   string
	ReadOnly bool
}

// ContainerInfo holds information about a running container.
type ContainerInfo struct {
	ID        string
	Name      string
	Image     string
	Status    string
	State     string
	IPAddress string
	Ports     map[string]string
	StartedAt time.Time
}

// StartContainer removes any existing container with the same name, then runs a new one.
func StartContainer(ctx context.Context, rt Runtime, cfg ContainerConfig) (string, error) {
	// Remove old container if present (ignore errors)
	_ = exec.CommandContext(ctx, rt.String(), "rm", "-f", cfg.Name).Run()

	args := []string{"run", "-d", "--name", cfg.Name}

	// Network
	if cfg.HostNetwork {
		args = append(args, "--network", "host")
	} else if cfg.NetworkName != "" {
		args = append(args, "--network", cfg.NetworkName)
	}

	// Restart policy
	if cfg.RestartPolicy != "" {
		args = append(args, "--restart", cfg.RestartPolicy)
	}

	// User
	if cfg.User != "" {
		args = append(args, "--user", cfg.User)
	}

	// Environment
	for _, e := range cfg.Env {
		args = append(args, "-e", e)
	}

	// Ports
	for containerPort, hostPort := range cfg.PortBindings {
		// containerPort is "9090/tcp" or just "9090"
		cp := strings.TrimSuffix(containerPort, "/tcp")
		if cfg.BindAddress != "" {
			args = append(args, "-p", fmt.Sprintf("%s:%s:%s", cfg.BindAddress, hostPort, cp))
		} else {
			args = append(args, "-p", fmt.Sprintf("%s:%s", hostPort, cp))
		}
	}

	// Mounts
	for _, m := range cfg.Mounts {
		mountStr := fmt.Sprintf("%s:%s", m.Source, m.Target)
		if m.ReadOnly {
			mountStr += ":ro"
		}
		args = append(args, "-v", mountStr)
	}

	// Extra hosts
	for _, h := range cfg.ExtraHosts {
		args = append(args, "--add-host", h)
	}

	// Extra args (e.g. podman --userns=keep-id)
	args = append(args, cfg.ExtraArgs...)

	// Image
	args = append(args, cfg.Image)

	// Command
	args = append(args, cfg.Cmd...)

	cmd := exec.CommandContext(ctx, rt.String(), args...)
	output, err := cmd.CombinedOutput()
	if err != nil {
		return "", fmt.Errorf("starting container %s: %w: %s", cfg.Name, err, output)
	}
	return strings.TrimSpace(string(output)), nil
}

// StopContainer stops and removes a container by name.
func StopContainer(ctx context.Context, rt Runtime, name string, gracePeriod time.Duration) error {
	timeout := int(gracePeriod.Seconds())
	stopCmd := exec.CommandContext(ctx, rt.String(), "stop", "-t", fmt.Sprintf("%d", timeout), name)
	if output, err := stopCmd.CombinedOutput(); err != nil {
		outStr := string(output)
		if strings.Contains(outStr, "No such container") || strings.Contains(outStr, "not found") {
			return nil
		}
		return fmt.Errorf("stopping container %s: %w: %s", name, err, outStr)
	}

	rmCmd := exec.CommandContext(ctx, rt.String(), "rm", "-f", name)
	if output, err := rmCmd.CombinedOutput(); err != nil {
		outStr := string(output)
		if strings.Contains(outStr, "No such container") || strings.Contains(outStr, "not found") {
			return nil
		}
		return fmt.Errorf("removing container %s: %w: %s", name, err, outStr)
	}
	return nil
}

// inspectJSON is the subset of docker inspect output we parse.
type inspectJSON struct {
	ID    string `json:"Id"`
	Name  string `json:"Name"`
	State struct {
		Status    string `json:"Status"`
		Running   bool   `json:"Running"`
		StartedAt string `json:"StartedAt"`
	} `json:"State"`
	Config struct {
		Image string `json:"Image"`
	} `json:"Config"`
	NetworkSettings struct {
		Networks map[string]struct {
			IPAddress string `json:"IPAddress"`
		} `json:"Networks"`
		Ports map[string][]struct {
			HostPort string `json:"HostPort"`
		} `json:"Ports"`
	} `json:"NetworkSettings"`
}

// InspectContainer returns information about a container.
func InspectContainer(ctx context.Context, rt Runtime, name string) (*ContainerInfo, error) {
	out, err := exec.CommandContext(ctx, rt.String(), "inspect", name).Output()
	if err != nil {
		return nil, fmt.Errorf("inspecting container %s: %w", name, err)
	}

	var inspections []inspectJSON
	if err := json.Unmarshal(out, &inspections); err != nil {
		return nil, fmt.Errorf("parsing inspect output: %w", err)
	}
	if len(inspections) == 0 {
		return nil, fmt.Errorf("no inspect data for %s", name)
	}

	info := inspections[0]
	ci := &ContainerInfo{
		ID:    info.ID,
		Name:  strings.TrimPrefix(info.Name, "/"),
		Image: info.Config.Image,
		State: info.State.Status,
	}

	if info.State.Running {
		ci.Status = "running"
	} else {
		ci.Status = info.State.Status
	}

	ci.StartedAt, _ = time.Parse(time.RFC3339Nano, info.State.StartedAt)

	for _, ep := range info.NetworkSettings.Networks {
		ci.IPAddress = ep.IPAddress
		break
	}

	ci.Ports = make(map[string]string)
	for port, bindings := range info.NetworkSettings.Ports {
		if len(bindings) > 0 {
			ci.Ports[port] = bindings[0].HostPort
		}
	}

	return ci, nil
}

// WaitForHealth polls an HTTP endpoint until it returns 200 or the retry limit is reached.
func WaitForHealth(ctx context.Context, url string, maxRetries int, interval time.Duration) error {
	httpClient := &http.Client{Timeout: 5 * time.Second}
	for i := 0; i < maxRetries; i++ {
		select {
		case <-ctx.Done():
			return ctx.Err()
		default:
		}

		resp, err := httpClient.Get(url)
		if err == nil {
			resp.Body.Close()
			if resp.StatusCode >= 200 && resp.StatusCode < 400 {
				return nil
			}
		}
		time.Sleep(interval)
	}
	return fmt.Errorf("health check failed after %d retries: %s", maxRetries, url)
}

// ContainerName returns the container name with optional port suffix.
func ContainerName(base string, port int, defaultPort int) string {
	if port != defaultPort && port != 0 {
		return fmt.Sprintf("%s-%d", base, port)
	}
	return base
}
