package docker

import (
	"context"
	"os/exec"
	"strings"
)

// Runtime represents the detected container runtime.
type Runtime int

const (
	RuntimeDocker Runtime = iota
	RuntimePodman
)

func (r Runtime) String() string {
	if r == RuntimePodman {
		return "podman"
	}
	return "docker"
}

// DetectRuntime detects whether Docker or Podman is available.
func DetectRuntime(ctx context.Context) (Runtime, error) {
	out, err := exec.CommandContext(ctx, "docker", "--help").CombinedOutput()
	if err != nil {
		return RuntimeDocker, err
	}
	if strings.Contains(strings.ToLower(string(out)), "podman") {
		return RuntimePodman, nil
	}
	return RuntimeDocker, nil
}

// ExtraArgs returns additional Docker/Podman arguments based on the runtime.
func ExtraArgs(rt Runtime) []string {
	if rt == RuntimePodman {
		return []string{"--userns=keep-id"}
	}
	return nil
}
