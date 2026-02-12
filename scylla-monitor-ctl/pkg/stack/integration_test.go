//go:build integration

package stack

import (
	"context"
	"fmt"
	"net"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/scylladb/scylla-monitoring/scylla-monitor-ctl/pkg/docker"
)

func freePort(t *testing.T) int {
	t.Helper()
	l, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("finding free port: %v", err)
	}
	defer l.Close()
	return l.Addr().(*net.TCPAddr).Port
}

func TestIntegrationDestroyCleanSlate(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()

	rt, err := docker.DetectRuntime(ctx)
	if err != nil {
		t.Fatalf("DetectRuntime: %v", err)
	}

	// Destroy on a clean slate should not error — all warnings are logged, not returned
	opts := DestroyOptions{
		StackID:          997,
		PrometheusPort:   freePort(t),
		GrafanaPort:      freePort(t),
		AlertManagerPort: freePort(t),
		LokiPort:         freePort(t),
		PromtailPort:     freePort(t),
		GracePeriod:      5 * time.Second,
		Runtime:          rt,
	}
	if err := Destroy(ctx, opts); err != nil {
		t.Fatalf("Destroy: %v", err)
	}
}

func TestIntegrationGetStatusEmpty(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	rt, err := docker.DetectRuntime(ctx)
	if err != nil {
		t.Fatalf("DetectRuntime: %v", err)
	}

	opts := StatusOptions{
		StackID:          996,
		PrometheusPort:   freePort(t),
		GrafanaPort:      freePort(t),
		AlertManagerPort: freePort(t),
		LokiPort:         freePort(t),
		PromtailPort:     freePort(t),
		Runtime:          rt,
	}

	status, err := GetStatus(ctx, opts)
	if err != nil {
		t.Fatalf("GetStatus: %v", err)
	}

	// All components should be "not found" since nothing is running
	for _, c := range status.Components {
		if c.Status != "not found" {
			t.Errorf("expected %s to be 'not found', got %q", c.Name, c.Status)
		}
	}

	table := status.FormatTable()
	if table == "" {
		t.Error("expected non-empty table output")
	}
	t.Log("\n" + table)
}

func TestIntegrationDeployDestroySingleContainer(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 120*time.Second)
	defer cancel()

	rt, err := docker.DetectRuntime(ctx)
	if err != nil {
		t.Fatalf("DetectRuntime: %v", err)
	}

	promPort := freePort(t)
	grafPort := freePort(t)
	stackID := 995

	// Ensure cleanup
	defer func() {
		cleanCtx, cleanCancel := context.WithTimeout(context.Background(), 30*time.Second)
		defer cleanCancel()
		Destroy(cleanCtx, DestroyOptions{
			StackID:        stackID,
			PrometheusPort: promPort,
			GrafanaPort:    grafPort,
			GracePeriod:    5 * time.Second,
			Runtime:        rt,
		})
	}()

	// Create a minimal prometheus config
	promDir := t.TempDir()
	promConfig := "global:\n  scrape_interval: 15s\nscrape_configs: []\n"
	if err := os.WriteFile(filepath.Join(promDir, "prometheus.yml"), []byte(promConfig), 0644); err != nil {
		t.Fatalf("writing prometheus.yml: %v", err)
	}

	// Create network
	if err := docker.CreateNetwork(ctx, rt, stackID); err != nil {
		t.Fatalf("CreateNetwork: %v", err)
	}

	// Start just Prometheus
	promName := docker.ContainerName("aprom", promPort, 9090)
	promCfg := docker.ContainerConfig{
		Name:        promName,
		Image:       "prom/prometheus:v3.2.1",
		NetworkName: docker.NetworkName(stackID),
		PortBindings: map[string]string{
			"9090/tcp": fmt.Sprintf("%d", promPort),
		},
		Mounts: []docker.MountConfig{
			{Source: filepath.Join(promDir, "prometheus.yml"), Target: "/etc/prometheus/prometheus.yml", ReadOnly: true},
		},
		Cmd: []string{
			"--config.file=/etc/prometheus/prometheus.yml",
			"--web.enable-lifecycle",
		},
	}
	_, err = docker.StartContainer(ctx, rt, promCfg)
	if err != nil {
		t.Fatalf("StartContainer(Prometheus): %v", err)
	}

	// Wait for health
	url := fmt.Sprintf("http://localhost:%d/-/healthy", promPort)
	if err := docker.WaitForHealth(ctx, url, 30, time.Second); err != nil {
		t.Fatalf("Prometheus health check: %v", err)
	}
	t.Logf("Prometheus healthy on port %d", promPort)

	// Check status
	statusOpts := StatusOptions{
		StackID:        stackID,
		PrometheusPort: promPort,
		GrafanaPort:    grafPort,
		Runtime:        rt,
	}
	status, err := GetStatus(ctx, statusOpts)
	if err != nil {
		t.Fatalf("GetStatus: %v", err)
	}

	foundRunning := false
	for _, c := range status.Components {
		if c.Name == "Prometheus" {
			if c.Status != "running" {
				t.Errorf("expected Prometheus status 'running', got %q", c.Status)
			}
			foundRunning = true
		}
	}
	if !foundRunning {
		t.Error("Prometheus not found in status")
	}
	t.Log("\n" + status.FormatTable())

	// Destroy
	destroyOpts := DestroyOptions{
		StackID:        stackID,
		PrometheusPort: promPort,
		GrafanaPort:    grafPort,
		GracePeriod:    10 * time.Second,
		Runtime:        rt,
	}
	if err := Destroy(ctx, destroyOpts); err != nil {
		t.Fatalf("Destroy: %v", err)
	}
	t.Log("Stack destroyed successfully")
}
