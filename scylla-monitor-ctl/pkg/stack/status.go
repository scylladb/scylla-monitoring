package stack

import (
	"context"
	"fmt"
	"strings"
	"time"

	"github.com/scylladb/scylla-monitoring/scylla-monitor-ctl/pkg/docker"
)

// ComponentStatus holds the status of a single stack component.
type ComponentStatus struct {
	Name      string
	Status    string // "running", "stopped", "not found"
	Image     string
	Address   string
	Uptime    time.Duration
}

// StackStatus holds the status of the entire monitoring stack.
type StackStatus struct {
	Components []ComponentStatus
}

// StatusOptions holds options for the status command.
type StatusOptions struct {
	StackID          int
	PrometheusPort   int
	GrafanaPort      int
	AlertManagerPort int
	LokiPort         int
	PromtailPort     int
	Runtime          docker.Runtime
}

// GetStatus collects the status of all stack components.
func GetStatus(ctx context.Context, opts StatusOptions) (*StackStatus, error) {
	rt := opts.Runtime

	components := []struct {
		displayName string
		container   string
		port        int
		defaultPort int
	}{
		{"Prometheus", "aprom", opts.PrometheusPort, 9090},
		{"Grafana", "agraf", opts.GrafanaPort, 3000},
		{"AlertManager", "aalert", opts.AlertManagerPort, 9093},
		{"Loki", "loki", opts.LokiPort, 3100},
		{"Promtail", "promtail", opts.PromtailPort, 9080},
		{"Renderer", "agrafrender", 0, 0},
	}

	var ss StackStatus
	for _, comp := range components {
		name := docker.ContainerName(comp.container, comp.port, comp.defaultPort)
		cs := ComponentStatus{Name: comp.displayName}

		info, err := docker.InspectContainer(ctx, rt, name)
		if err != nil {
			cs.Status = "not found"
			ss.Components = append(ss.Components, cs)
			continue
		}

		cs.Status = info.Status
		cs.Image = info.Image
		if !info.StartedAt.IsZero() {
			cs.Uptime = time.Since(info.StartedAt)
		}
		if info.IPAddress != "" {
			cs.Address = info.IPAddress
		}
		for port, hostPort := range info.Ports {
			cs.Address = fmt.Sprintf("localhost:%s (%s)", hostPort, port)
			break
		}

		ss.Components = append(ss.Components, cs)
	}

	return &ss, nil
}

// FormatTable returns a formatted table of the stack status.
func (ss *StackStatus) FormatTable() string {
	var sb strings.Builder
	sb.WriteString(fmt.Sprintf("%-16s %-10s %-40s %-15s\n", "Component", "Status", "Image", "Uptime"))
	sb.WriteString(strings.Repeat("-", 85) + "\n")
	for _, c := range ss.Components {
		uptime := ""
		if c.Uptime > 0 {
			uptime = formatDuration(c.Uptime)
		}
		image := c.Image
		if len(image) > 40 {
			image = image[:37] + "..."
		}
		sb.WriteString(fmt.Sprintf("%-16s %-10s %-40s %-15s\n", c.Name, c.Status, image, uptime))
	}
	return sb.String()
}

func formatDuration(d time.Duration) string {
	days := int(d.Hours()) / 24
	hours := int(d.Hours()) % 24
	if days > 0 {
		return fmt.Sprintf("%dd %dh", days, hours)
	}
	minutes := int(d.Minutes()) % 60
	if hours > 0 {
		return fmt.Sprintf("%dh %dm", hours, minutes)
	}
	return fmt.Sprintf("%dm", minutes)
}
