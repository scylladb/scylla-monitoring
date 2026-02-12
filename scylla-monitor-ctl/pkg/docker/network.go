package docker

import (
	"context"
	"fmt"
	"os/exec"
	"strings"
)

const baseNetworkName = "monitor-net"

// NetworkName returns the Docker network name for a given stack ID.
// Stack 0 uses "monitor-net", others use "monitor-net<id>".
func NetworkName(stackID int) string {
	if stackID <= 0 {
		return baseNetworkName
	}
	return fmt.Sprintf("%s%d", baseNetworkName, stackID)
}

// CreateNetwork creates the monitoring Docker network if it doesn't exist.
func CreateNetwork(ctx context.Context, rt Runtime, stackID int) error {
	name := NetworkName(stackID)

	// Check if network already exists
	out, err := exec.CommandContext(ctx, rt.String(), "network", "ls", "--filter", "name=^"+name+"$", "--format", "{{.Name}}").Output()
	if err == nil && strings.TrimSpace(string(out)) == name {
		return nil // already exists
	}

	cmd := exec.CommandContext(ctx, rt.String(), "network", "create", name)
	if output, err := cmd.CombinedOutput(); err != nil {
		return fmt.Errorf("creating network %s: %w: %s", name, err, output)
	}
	return nil
}

// RemoveNetwork removes the monitoring Docker network.
func RemoveNetwork(ctx context.Context, rt Runtime, stackID int) error {
	name := NetworkName(stackID)
	cmd := exec.CommandContext(ctx, rt.String(), "network", "rm", name)
	if output, err := cmd.CombinedOutput(); err != nil {
		// Ignore "not found" errors
		if strings.Contains(string(output), "not found") || strings.Contains(string(output), "No such network") {
			return nil
		}
		return fmt.Errorf("removing network %s: %w: %s", name, err, output)
	}
	return nil
}
