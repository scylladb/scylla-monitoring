package versions

import (
	"os"
	"testing"
)

func loadTestMatrix(t *testing.T) *Matrix {
	t.Helper()
	data, err := os.ReadFile("../../assets/versions.yaml")
	if err != nil {
		t.Fatalf("reading versions.yaml: %v", err)
	}
	m, err := Parse(data)
	if err != nil {
		t.Fatalf("parsing versions.yaml: %v", err)
	}
	return m
}

func TestParse(t *testing.T) {
	m := loadTestMatrix(t)
	if len(m.StackVersions) == 0 {
		t.Fatal("expected non-empty stack versions")
	}
	if m.ContainerImages.Prometheus == "" {
		t.Fatal("expected prometheus container image version")
	}
}

func TestSupportedVersions(t *testing.T) {
	m := loadTestMatrix(t)
	versions, err := m.SupportedScyllaVersions("4.14")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(versions) == 0 {
		t.Fatal("expected non-empty supported versions for 4.14")
	}
	found := false
	for _, v := range versions {
		if v == "2025.3" {
			found = true
			break
		}
	}
	if !found {
		t.Errorf("expected 2025.3 in supported versions for 4.14, got %v", versions)
	}
}

func TestDefaultVersions(t *testing.T) {
	m := loadTestMatrix(t)

	tests := []struct {
		stack    string
		expected string
	}{
		{"4.14", "2025.3"},
		{"4.9", "6.2"},
		{"4.8", "6.0"},
		{"3.8", "4.4"},
	}
	for _, tt := range tests {
		t.Run(tt.stack, func(t *testing.T) {
			v, err := m.DefaultScyllaVersion(tt.stack)
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if v != tt.expected {
				t.Errorf("expected default %s for stack %s, got %s", tt.expected, tt.stack, v)
			}
		})
	}
}

func TestDefaultManagerVersions(t *testing.T) {
	m := loadTestMatrix(t)

	tests := []struct {
		stack    string
		expected string
	}{
		{"4.14", "3"},
		{"4.9", "3.4"},
		{"4.0", "3.0"},
	}
	for _, tt := range tests {
		t.Run(tt.stack, func(t *testing.T) {
			v, err := m.DefaultManagerVersion(tt.stack)
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if v != tt.expected {
				t.Errorf("expected manager default %s for stack %s, got %s", tt.expected, tt.stack, v)
			}
		})
	}
}

func TestPortLookup(t *testing.T) {
	m := loadTestMatrix(t)

	ports, err := m.GetPorts(1)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if ports.Prometheus != 9051 {
		t.Errorf("expected prometheus port 9051 for stack 1, got %d", ports.Prometheus)
	}
	if ports.Grafana != 3001 {
		t.Errorf("expected grafana port 3001 for stack 1, got %d", ports.Grafana)
	}
	if ports.AlertManager != 9041 {
		t.Errorf("expected alertmanager port 9041 for stack 1, got %d", ports.AlertManager)
	}

	_, err = m.GetPorts(99)
	if err == nil {
		t.Error("expected error for invalid stack ID")
	}
}

func TestUnknownStackVersion(t *testing.T) {
	m := loadTestMatrix(t)
	_, err := m.SupportedScyllaVersions("99.99")
	if err == nil {
		t.Error("expected error for unknown stack version")
	}
}

func TestContainerImages(t *testing.T) {
	m := loadTestMatrix(t)
	if m.ContainerImages.Prometheus != "v3.9.1" {
		t.Errorf("expected prometheus v3.9.1, got %s", m.ContainerImages.Prometheus)
	}
	if m.ContainerImages.Grafana != "12.3.2" {
		t.Errorf("expected grafana 12.3.2, got %s", m.ContainerImages.Grafana)
	}
	if m.ContainerImages.AlertManager != "v0.30.1" {
		t.Errorf("expected alertmanager v0.30.1, got %s", m.ContainerImages.AlertManager)
	}
}

func TestDefaultDashboards(t *testing.T) {
	m := loadTestMatrix(t)
	expected := []string{"scylla-overview", "scylla-detailed", "scylla-os", "scylla-cql", "scylla-advanced", "alternator", "scylla-ks"}
	if len(m.DefaultDashboards) != len(expected) {
		t.Fatalf("expected %d default dashboards, got %d", len(expected), len(m.DefaultDashboards))
	}
	for i, d := range expected {
		if m.DefaultDashboards[i] != d {
			t.Errorf("expected dashboard %d to be %s, got %s", i, d, m.DefaultDashboards[i])
		}
	}
}

func TestLatestStackVersion(t *testing.T) {
	m := loadTestMatrix(t)
	latest := m.LatestStackVersion()
	if latest != "4.14" {
		t.Errorf("expected latest stack version 4.14, got %s", latest)
	}
}

func TestCompareVersionStrings(t *testing.T) {
	tests := []struct {
		a, b     string
		expected int
	}{
		{"4.14", "4.9", 1},
		{"4.9", "4.14", -1},
		{"4.9", "4.9", 0},
		{"5.0", "4.14", 1},
		{"3.8", "4.0", -1},
		{"4.14", "4.14", 0},
	}
	for _, tt := range tests {
		t.Run(tt.a+"_vs_"+tt.b, func(t *testing.T) {
			result := compareVersionStrings(tt.a, tt.b)
			if result != tt.expected {
				t.Errorf("compareVersionStrings(%q, %q) = %d, want %d", tt.a, tt.b, result, tt.expected)
			}
		})
	}
}
