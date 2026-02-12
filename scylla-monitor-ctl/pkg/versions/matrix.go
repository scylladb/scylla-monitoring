package versions

import (
	"fmt"
	"strconv"
	"strings"

	"gopkg.in/yaml.v3"
)

// StackVersion holds version information for a specific monitoring stack release.
type StackVersion struct {
	SupportedScylla   []string `yaml:"supported_scylla"`
	DefaultScylla     string   `yaml:"default_scylla"`
	DefaultEnterprise string   `yaml:"default_enterprise"`
	ManagerSupported  []string `yaml:"manager_supported"`
	ManagerDefault    string   `yaml:"manager_default"`
	VectorDefault     string   `yaml:"vector_default,omitempty"`
}

// PortSet holds port numbers for a stack instance.
type PortSet struct {
	Prometheus   int `yaml:"prometheus"`
	Grafana      int `yaml:"grafana"`
	AlertManager int `yaml:"alertmanager"`
}

// ContainerImages holds container image versions.
type ContainerImages struct {
	Prometheus      string `yaml:"prometheus"`
	AlertManager    string `yaml:"alertmanager"`
	Grafana         string `yaml:"grafana"`
	Loki            string `yaml:"loki"`
	GrafanaRenderer string `yaml:"grafana_renderer"`
	VictoriaMetrics string `yaml:"victoria_metrics"`
}

// Matrix holds the complete version compatibility matrix.
type Matrix struct {
	StackVersions     map[string]StackVersion `yaml:"stack_versions"`
	ContainerImages   ContainerImages         `yaml:"container_images"`
	StackPorts        map[int]PortSet         `yaml:"stack_ports"`
	DefaultDashboards []string                `yaml:"default_dashboards"`
}

// Parse parses a versions.yaml file into a Matrix.
func Parse(data []byte) (*Matrix, error) {
	var m Matrix
	if err := yaml.Unmarshal(data, &m); err != nil {
		return nil, fmt.Errorf("parsing versions.yaml: %w", err)
	}
	return &m, nil
}

// GetStackVersion returns the StackVersion for the given stack version string.
func (m *Matrix) GetStackVersion(ver string) (StackVersion, bool) {
	sv, ok := m.StackVersions[ver]
	return sv, ok
}

// SupportedScyllaVersions returns the list of supported ScyllaDB versions for a stack version.
func (m *Matrix) SupportedScyllaVersions(stackVer string) ([]string, error) {
	sv, ok := m.StackVersions[stackVer]
	if !ok {
		return nil, fmt.Errorf("unknown stack version: %s", stackVer)
	}
	return sv.SupportedScylla, nil
}

// DefaultScyllaVersion returns the default ScyllaDB version for a stack version.
func (m *Matrix) DefaultScyllaVersion(stackVer string) (string, error) {
	sv, ok := m.StackVersions[stackVer]
	if !ok {
		return "", fmt.Errorf("unknown stack version: %s", stackVer)
	}
	return sv.DefaultScylla, nil
}

// DefaultManagerVersion returns the default Manager version for a stack version.
func (m *Matrix) DefaultManagerVersion(stackVer string) (string, error) {
	sv, ok := m.StackVersions[stackVer]
	if !ok {
		return "", fmt.Errorf("unknown stack version: %s", stackVer)
	}
	return sv.ManagerDefault, nil
}

// GetPorts returns the port set for a given stack ID.
func (m *Matrix) GetPorts(stackID int) (PortSet, error) {
	ps, ok := m.StackPorts[stackID]
	if !ok {
		return PortSet{}, fmt.Errorf("unknown stack ID: %d", stackID)
	}
	return ps, nil
}

// compareVersionStrings compares two dotted version strings numerically.
// Returns 1 if a > b, -1 if a < b, 0 if equal.
func compareVersionStrings(a, b string) int {
	aParts := strings.Split(a, ".")
	bParts := strings.Split(b, ".")
	maxLen := len(aParts)
	if len(bParts) > maxLen {
		maxLen = len(bParts)
	}
	for i := 0; i < maxLen; i++ {
		var aVal, bVal int
		if i < len(aParts) {
			aVal, _ = strconv.Atoi(aParts[i])
		}
		if i < len(bParts) {
			bVal, _ = strconv.Atoi(bParts[i])
		}
		if aVal > bVal {
			return 1
		}
		if aVal < bVal {
			return -1
		}
	}
	return 0
}

// LatestStackVersion returns the latest (highest numbered) stack version key.
func (m *Matrix) LatestStackVersion() string {
	var latest string
	for k := range m.StackVersions {
		if latest == "" || compareVersionStrings(k, latest) > 0 {
			latest = k
		}
	}
	return latest
}
