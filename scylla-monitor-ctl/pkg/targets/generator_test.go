package targets

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"gopkg.in/yaml.v3"
)

func TestGenerateTargets_Simple(t *testing.T) {
	groups, err := GenerateTargets([]string{"dc1:10.0.0.1,10.0.0.2"}, "my-cluster", "")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(groups) != 1 {
		t.Fatalf("expected 1 group, got %d", len(groups))
	}
	if groups[0].Labels["cluster"] != "my-cluster" {
		t.Errorf("expected cluster=my-cluster, got %s", groups[0].Labels["cluster"])
	}
	if groups[0].Labels["dc"] != "dc1" {
		t.Errorf("expected dc=dc1, got %s", groups[0].Labels["dc"])
	}
	if len(groups[0].Targets) != 2 {
		t.Errorf("expected 2 targets, got %d", len(groups[0].Targets))
	}
}

func TestGenerateTargets_MultipleDCs(t *testing.T) {
	groups, err := GenerateTargets([]string{
		"dc1:10.0.0.1,10.0.0.2",
		"dc2:10.0.0.3",
	}, "test-cluster", "")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(groups) != 2 {
		t.Fatalf("expected 2 groups, got %d", len(groups))
	}
	if groups[0].Labels["dc"] != "dc1" {
		t.Errorf("expected dc1, got %s", groups[0].Labels["dc"])
	}
	if groups[1].Labels["dc"] != "dc2" {
		t.Errorf("expected dc2, got %s", groups[1].Labels["dc"])
	}
}

func TestGenerateTargets_WithAlias(t *testing.T) {
	groups, err := GenerateTargets([]string{
		"dc1:192.0.2.1=node1,192.0.2.2=node2,192.0.2.3",
	}, "my-cluster", "=")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	// Should have 3 groups: 1 plain + 2 aliased
	if len(groups) != 3 {
		t.Fatalf("expected 3 groups, got %d", len(groups))
	}
	// First should be the plain IP
	if len(groups[0].Targets) != 1 || groups[0].Targets[0] != "192.0.2.3" {
		t.Errorf("expected plain target 192.0.2.3, got %v", groups[0].Targets)
	}
	// Second should be aliased
	if groups[1].Labels["instance"] != "node1" {
		t.Errorf("expected instance=node1, got %s", groups[1].Labels["instance"])
	}
	if groups[1].Targets[0] != "192.0.2.1" {
		t.Errorf("expected target 192.0.2.1, got %s", groups[1].Targets[0])
	}
}

func TestGenerateTargets_AllAliased(t *testing.T) {
	groups, err := GenerateTargets([]string{
		"dc1:192.0.2.1=node1,192.0.2.2=node2",
	}, "my-cluster", "=")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(groups) != 2 {
		t.Fatalf("expected 2 groups, got %d", len(groups))
	}
}

func TestGenerateTargets_MissingDC(t *testing.T) {
	_, err := GenerateTargets([]string{"10.0.0.1,10.0.0.2"}, "cluster", "")
	if err == nil {
		t.Error("expected error for missing DC separator")
	}
}

func TestParseNodetoolStatus(t *testing.T) {
	input := `Datacenter: dc1
==============
Status=Up/Down
|/ State=Normal/Leaving/Joining/Moving
--  Address      Load       Tokens  Owns    Host ID                               Rack
UN  10.0.0.1    1.5 GB     256     33.3%   abc-def                               rack1
UN  10.0.0.2    1.2 GB     256     33.3%   def-ghi                               rack1
Datacenter: dc2
==============
Status=Up/Down
|/ State=Normal/Leaving/Joining/Moving
--  Address      Load       Tokens  Owns    Host ID                               Rack
UN  10.0.0.3    1.8 GB     256     33.3%   ghi-jkl                               rack1
`
	result, err := ParseNodetoolStatus(strings.NewReader(input))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(result) != 2 {
		t.Fatalf("expected 2 DC entries, got %d: %v", len(result), result)
	}
	if result[0] != "dc1:10.0.0.1,10.0.0.2" {
		t.Errorf("expected dc1:10.0.0.1,10.0.0.2, got %s", result[0])
	}
	if result[1] != "dc2:10.0.0.3" {
		t.Errorf("expected dc2:10.0.0.3, got %s", result[1])
	}
}

func TestWriteTargetsFile(t *testing.T) {
	groups := []TargetGroup{
		{
			Targets: []string{"10.0.0.1", "10.0.0.2"},
			Labels:  map[string]string{"cluster": "test", "dc": "dc1"},
		},
	}

	dir := t.TempDir()
	err := WriteTargetsFile(groups, dir, "test_servers.yml")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	data, err := os.ReadFile(filepath.Join(dir, "test_servers.yml"))
	if err != nil {
		t.Fatalf("reading file: %v", err)
	}

	// Verify it's valid YAML
	var parsed []TargetGroup
	if err := yaml.Unmarshal(data, &parsed); err != nil {
		t.Fatalf("invalid YAML: %v", err)
	}
	if len(parsed) != 1 {
		t.Fatalf("expected 1 group, got %d", len(parsed))
	}
	if parsed[0].Labels["cluster"] != "test" {
		t.Errorf("expected cluster=test, got %s", parsed[0].Labels["cluster"])
	}
}

func TestWriteTargetsSimple(t *testing.T) {
	dir := t.TempDir()
	err := WriteTargetsSimple([]string{"10.0.0.1", "10.0.0.2"}, dir, "simple.yml")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	data, err := os.ReadFile(filepath.Join(dir, "simple.yml"))
	if err != nil {
		t.Fatalf("reading file: %v", err)
	}

	var parsed []TargetGroup
	if err := yaml.Unmarshal(data, &parsed); err != nil {
		t.Fatalf("invalid YAML: %v", err)
	}
	if len(parsed[0].Targets) != 2 {
		t.Errorf("expected 2 targets, got %d", len(parsed[0].Targets))
	}
}
