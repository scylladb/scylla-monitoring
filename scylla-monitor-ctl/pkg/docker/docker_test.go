package docker

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestNetworkName(t *testing.T) {
	tests := []struct {
		stackID  int
		expected string
	}{
		{0, "monitor-net"},
		{-1, "monitor-net"},
		{1, "monitor-net1"},
		{2, "monitor-net2"},
		{4, "monitor-net4"},
	}
	for _, tt := range tests {
		result := NetworkName(tt.stackID)
		if result != tt.expected {
			t.Errorf("NetworkName(%d) = %q, want %q", tt.stackID, result, tt.expected)
		}
	}
}

func TestContainerName(t *testing.T) {
	tests := []struct {
		base        string
		port        int
		defaultPort int
		expected    string
	}{
		{"aprom", 9090, 9090, "aprom"},
		{"aprom", 9091, 9090, "aprom-9091"},
		{"agraf", 3000, 3000, "agraf"},
		{"agraf", 3001, 3000, "agraf-3001"},
		{"aalert", 0, 9093, "aalert"},
	}
	for _, tt := range tests {
		result := ContainerName(tt.base, tt.port, tt.defaultPort)
		if result != tt.expected {
			t.Errorf("ContainerName(%q, %d, %d) = %q, want %q", tt.base, tt.port, tt.defaultPort, result, tt.expected)
		}
	}
}

func TestExtraArgs(t *testing.T) {
	args := ExtraArgs(RuntimeDocker)
	if len(args) != 0 {
		t.Errorf("expected no extra args for Docker, got %v", args)
	}
	args = ExtraArgs(RuntimePodman)
	if len(args) != 1 || args[0] != "--userns=keep-id" {
		t.Errorf("expected [--userns=keep-id] for Podman, got %v", args)
	}
}

func TestRuntimeString(t *testing.T) {
	if RuntimeDocker.String() != "docker" {
		t.Errorf("expected 'docker', got %q", RuntimeDocker.String())
	}
	if RuntimePodman.String() != "podman" {
		t.Errorf("expected 'podman', got %q", RuntimePodman.String())
	}
}

func TestGenerateCompose(t *testing.T) {
	tmpl := []byte(`version: '3'
services:
  prometheus:
    image: prom/prometheus:${PROMETHEUS_VERSION}
    command:
#PROMETHEUS_COMMAND_LINE
  grafana:
    image: grafana/grafana:${GRAFANA_VERSION}
    environment:
#GRAFANA_ENV
#GENERAL_DOCER_CONFIG
`)
	dir := t.TempDir()
	opts := ComposeOptions{
		Template:            tmpl,
		OutputDir:           dir,
		PrometheusVersion:   "v3.9.1",
		AlertManagerVersion: "v0.30.1",
		GrafanaVersion:      "12.3.2",
		LokiVersion:         "3.6.4",
		PrometheusPort:      9090,
		GrafanaPort:         3000,
		AlertManagerPort:    9093,
		LokiPort:            3100,
		AdminPassword:       "admin",
		Anonymous:           true,
		AnonymousRole:       "Admin",
		RestartPolicy:       "unless-stopped",
	}

	if err := GenerateCompose(opts); err != nil {
		t.Fatalf("GenerateCompose: %v", err)
	}

	// Check compose file exists
	composeData, err := os.ReadFile(filepath.Join(dir, "docker-compose.yml"))
	if err != nil {
		t.Fatalf("reading docker-compose.yml: %v", err)
	}
	if !strings.Contains(string(composeData), "restart: unless-stopped") {
		t.Error("expected restart policy in compose file")
	}

	// Check .env file
	envData, err := os.ReadFile(filepath.Join(dir, ".env"))
	if err != nil {
		t.Fatalf("reading .env: %v", err)
	}
	envStr := string(envData)
	if !strings.Contains(envStr, "PROMETHEUS_VERSION=v3.9.1") {
		t.Error("expected PROMETHEUS_VERSION in .env")
	}
	if !strings.Contains(envStr, "GRAFANA_VERSION=12.3.2") {
		t.Error("expected GRAFANA_VERSION in .env")
	}
	if !strings.Contains(envStr, "GF_SECURITY_ADMIN_PASSWORD=admin") {
		t.Error("expected admin password in .env")
	}
}
