//go:build integration

package docker

import (
	"context"
	"fmt"
	"net"
	"testing"
	"time"
)

// freePort returns an available TCP port on localhost.
func freePort(t *testing.T) int {
	t.Helper()
	l, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("finding free port: %v", err)
	}
	defer l.Close()
	return l.Addr().(*net.TCPAddr).Port
}

func TestIntegrationDetectRuntime(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	rt, err := DetectRuntime(ctx)
	if err != nil {
		t.Fatalf("DetectRuntime: %v", err)
	}
	if rt != RuntimeDocker && rt != RuntimePodman {
		t.Fatalf("unexpected runtime: %v", rt)
	}
	t.Logf("Detected runtime: %s", rt)
}

func TestIntegrationNetworkLifecycle(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	rt, err := DetectRuntime(ctx)
	if err != nil {
		t.Fatalf("DetectRuntime: %v", err)
	}

	// Use a high stack ID to avoid collisions with real stacks
	stackID := 999
	networkName := NetworkName(stackID)

	// Cleanup in case of previous failed run
	_ = RemoveNetwork(ctx, rt, stackID)

	// Create
	if err := CreateNetwork(ctx, rt, stackID); err != nil {
		t.Fatalf("CreateNetwork: %v", err)
	}
	t.Logf("Created network: %s", networkName)

	// Create again (idempotent)
	if err := CreateNetwork(ctx, rt, stackID); err != nil {
		t.Fatalf("CreateNetwork (idempotent): %v", err)
	}

	// Remove
	if err := RemoveNetwork(ctx, rt, stackID); err != nil {
		t.Fatalf("RemoveNetwork: %v", err)
	}
	t.Logf("Removed network: %s", networkName)

	// Remove again (idempotent)
	if err := RemoveNetwork(ctx, rt, stackID); err != nil {
		t.Fatalf("RemoveNetwork (idempotent): %v", err)
	}
}

func TestIntegrationContainerLifecycle(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()

	rt, err := DetectRuntime(ctx)
	if err != nil {
		t.Fatalf("DetectRuntime: %v", err)
	}

	containerName := "scylla-monitor-ctl-integration-test"
	hostPort := freePort(t)

	// Cleanup from any previous failed run
	_ = StopContainer(ctx, rt, containerName, 5*time.Second)

	// Start an nginx container
	cfg := ContainerConfig{
		Name:         containerName,
		Image:        "nginx:alpine",
		PortBindings: map[string]string{"80/tcp": fmt.Sprintf("%d", hostPort)},
	}
	id, err := StartContainer(ctx, rt, cfg)
	if err != nil {
		t.Fatalf("StartContainer: %v", err)
	}
	t.Logf("Started container %s (id=%s) on port %d", containerName, id[:12], hostPort)

	// Inspect
	info, err := InspectContainer(ctx, rt, containerName)
	if err != nil {
		t.Fatalf("InspectContainer: %v", err)
	}
	if info.Status != "running" {
		t.Errorf("expected status 'running', got %q", info.Status)
	}
	if info.Image != "nginx:alpine" {
		t.Errorf("expected image 'nginx:alpine', got %q", info.Image)
	}
	t.Logf("Container status: %s, image: %s", info.Status, info.Image)

	// Health check
	url := fmt.Sprintf("http://localhost:%d/", hostPort)
	if err := WaitForHealth(ctx, url, 15, time.Second); err != nil {
		t.Fatalf("WaitForHealth: %v", err)
	}
	t.Log("Health check passed")

	// Stop
	if err := StopContainer(ctx, rt, containerName, 10*time.Second); err != nil {
		t.Fatalf("StopContainer: %v", err)
	}
	t.Log("Container stopped and removed")

	// Inspect after stop should fail
	_, err = InspectContainer(ctx, rt, containerName)
	if err == nil {
		t.Error("expected error inspecting removed container")
	}
}

func TestIntegrationContainerWithNetwork(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()

	rt, err := DetectRuntime(ctx)
	if err != nil {
		t.Fatalf("DetectRuntime: %v", err)
	}

	stackID := 998
	containerName := "scylla-monitor-ctl-net-test"
	hostPort := freePort(t)

	// Cleanup
	_ = StopContainer(ctx, rt, containerName, 5*time.Second)
	_ = RemoveNetwork(ctx, rt, stackID)

	// Create network
	if err := CreateNetwork(ctx, rt, stackID); err != nil {
		t.Fatalf("CreateNetwork: %v", err)
	}
	defer RemoveNetwork(ctx, rt, stackID)

	networkName := NetworkName(stackID)

	// Start container on network
	cfg := ContainerConfig{
		Name:         containerName,
		Image:        "nginx:alpine",
		NetworkName:  networkName,
		PortBindings: map[string]string{"80/tcp": fmt.Sprintf("%d", hostPort)},
	}
	_, err = StartContainer(ctx, rt, cfg)
	if err != nil {
		t.Fatalf("StartContainer: %v", err)
	}
	defer StopContainer(ctx, rt, containerName, 10*time.Second)

	// Inspect — should have an IP on the custom network
	info, err := InspectContainer(ctx, rt, containerName)
	if err != nil {
		t.Fatalf("InspectContainer: %v", err)
	}
	if info.Status != "running" {
		t.Errorf("expected running, got %q", info.Status)
	}
	if info.IPAddress == "" {
		t.Error("expected non-empty IP address on custom network")
	}
	t.Logf("Container IP on %s: %s", networkName, info.IPAddress)

	// Health check via port binding
	url := fmt.Sprintf("http://localhost:%d/", hostPort)
	if err := WaitForHealth(ctx, url, 15, time.Second); err != nil {
		t.Fatalf("WaitForHealth: %v", err)
	}
}

func TestIntegrationStartContainerIdempotent(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()

	rt, err := DetectRuntime(ctx)
	if err != nil {
		t.Fatalf("DetectRuntime: %v", err)
	}

	containerName := "scylla-monitor-ctl-idempotent-test"
	hostPort := freePort(t)

	// Cleanup
	_ = StopContainer(ctx, rt, containerName, 5*time.Second)

	cfg := ContainerConfig{
		Name:         containerName,
		Image:        "nginx:alpine",
		PortBindings: map[string]string{"80/tcp": fmt.Sprintf("%d", hostPort)},
	}

	// Start first time
	id1, err := StartContainer(ctx, rt, cfg)
	if err != nil {
		t.Fatalf("StartContainer (first): %v", err)
	}

	// Start again with same name — should succeed (removes old container)
	id2, err := StartContainer(ctx, rt, cfg)
	if err != nil {
		t.Fatalf("StartContainer (second): %v", err)
	}
	defer StopContainer(ctx, rt, containerName, 10*time.Second)

	if id1 == id2 {
		t.Error("expected different container IDs after re-creation")
	}
	t.Logf("First ID: %s, Second ID: %s", id1[:12], id2[:12])

	// Should be running
	info, err := InspectContainer(ctx, rt, containerName)
	if err != nil {
		t.Fatalf("InspectContainer: %v", err)
	}
	if info.Status != "running" {
		t.Errorf("expected running, got %q", info.Status)
	}
}

func TestIntegrationStopNonexistent(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()

	rt, err := DetectRuntime(ctx)
	if err != nil {
		t.Fatalf("DetectRuntime: %v", err)
	}

	// Stopping a non-existent container should not return an error
	err = StopContainer(ctx, rt, "nonexistent-container-12345", 5*time.Second)
	if err != nil {
		t.Errorf("expected nil error for non-existent container, got: %v", err)
	}
}
