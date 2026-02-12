package targets

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"gopkg.in/yaml.v3"
)

const relRepoRoot = "../../.."

func absRepoRoot(t *testing.T) string {
	t.Helper()
	abs, err := filepath.Abs(relRepoRoot)
	if err != nil {
		t.Fatalf("resolving repo root: %v", err)
	}
	return abs
}

func pythonAvailable(t *testing.T) bool {
	t.Helper()
	_, err := exec.LookPath("python3")
	return err == nil
}

// generateWithPythonGenconfig runs genconfig.py and returns parsed YAML.
func generateWithPythonGenconfig(t *testing.T, dcs []string, cluster string) ([]TargetGroup, error) {
	t.Helper()

	root := absRepoRoot(t)
	outDir := t.TempDir()
	scriptPath := filepath.Join(root, "genconfig.py")

	args := []string{
		scriptPath,
		"-d", outDir,
		"-c", cluster,
		"-o", "targets.yml",
	}
	for _, dc := range dcs {
		args = append(args, "-dc", dc)
	}

	cmd := exec.Command("python3", args...)
	cmd.Dir = root
	output, err := cmd.CombinedOutput()
	if err != nil {
		return nil, fmt.Errorf("genconfig.py failed: %v\noutput: %s", err, output)
	}

	data, err := os.ReadFile(filepath.Join(outDir, "targets.yml"))
	if err != nil {
		return nil, fmt.Errorf("reading python output: %v", err)
	}

	var result []TargetGroup
	if err := yaml.Unmarshal(data, &result); err != nil {
		return nil, fmt.Errorf("parsing python YAML: %v", err)
	}
	return result, nil
}

// TestPythonGoTargetCompatibility_BasicDC tests basic DC targets generation.
func TestPythonGoTargetCompatibility_BasicDC(t *testing.T) {
	if !pythonAvailable(t) {
		t.Skip("python3 not available")
	}

	tests := []struct {
		name    string
		dcs     []string
		cluster string
	}{
		{
			"single DC two nodes",
			[]string{"dc1:10.0.0.1,10.0.0.2"},
			"my-cluster",
		},
		{
			"two DCs",
			[]string{"dc1:10.0.0.1,10.0.0.2", "dc2:10.0.0.3,10.0.0.4"},
			"test-cluster",
		},
		{
			"single node",
			[]string{"us-east-1:192.168.1.100"},
			"prod",
		},
		{
			"three DCs three nodes each",
			[]string{
				"dc1:10.0.1.1,10.0.1.2,10.0.1.3",
				"dc2:10.0.2.1,10.0.2.2,10.0.2.3",
				"dc3:10.0.3.1,10.0.3.2,10.0.3.3",
			},
			"large-cluster",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			pyGroups, err := generateWithPythonGenconfig(t, tt.dcs, tt.cluster)
			if err != nil {
				t.Fatalf("Python generation failed: %v", err)
			}

			goGroups, err := GenerateTargets(tt.dcs, tt.cluster, "")
			if err != nil {
				t.Fatalf("Go generation failed: %v", err)
			}

			if len(pyGroups) != len(goGroups) {
				t.Fatalf("Group count mismatch: python=%d, go=%d", len(pyGroups), len(goGroups))
			}

			for i := range pyGroups {
				if len(pyGroups[i].Targets) != len(goGroups[i].Targets) {
					t.Errorf("Group %d target count: python=%d, go=%d",
						i, len(pyGroups[i].Targets), len(goGroups[i].Targets))
					continue
				}
				for j := range pyGroups[i].Targets {
					if pyGroups[i].Targets[j] != goGroups[i].Targets[j] {
						t.Errorf("Group %d target %d: python=%q, go=%q",
							i, j, pyGroups[i].Targets[j], goGroups[i].Targets[j])
					}
				}
				if pyGroups[i].Labels["cluster"] != goGroups[i].Labels["cluster"] {
					t.Errorf("Group %d cluster: python=%q, go=%q",
						i, pyGroups[i].Labels["cluster"], goGroups[i].Labels["cluster"])
				}
				if pyGroups[i].Labels["dc"] != goGroups[i].Labels["dc"] {
					t.Errorf("Group %d dc: python=%q, go=%q",
						i, pyGroups[i].Labels["dc"], goGroups[i].Labels["dc"])
				}
			}
		})
	}
}

// TestPythonGoTargetCompatibility_WithAlias tests alias support.
func TestPythonGoTargetCompatibility_WithAlias(t *testing.T) {
	if !pythonAvailable(t) {
		t.Skip("python3 not available")
	}

	root := absRepoRoot(t)
	outDir := t.TempDir()
	scriptPath := filepath.Join(root, "genconfig.py")

	// Python genconfig with alias separator
	args := []string{
		scriptPath,
		"-d", outDir,
		"-c", "alias-cluster",
		"-o", "targets.yml",
		"-a", "=",
		"-dc", "dc1:192.0.2.1=node1,192.0.2.2=node2,192.0.2.3",
	}

	cmd := exec.Command("python3", args...)
	cmd.Dir = root
	output, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("Python genconfig.py failed: %v\noutput: %s", err, output)
	}

	pyData, err := os.ReadFile(filepath.Join(outDir, "targets.yml"))
	if err != nil {
		t.Fatalf("reading python output: %v", err)
	}

	var pyGroups []TargetGroup
	if err := yaml.Unmarshal(pyData, &pyGroups); err != nil {
		t.Fatalf("parsing python YAML: %v", err)
	}

	// Go generation
	goGroups, err := GenerateTargets(
		[]string{"dc1:192.0.2.1=node1,192.0.2.2=node2,192.0.2.3"},
		"alias-cluster",
		"=",
	)
	if err != nil {
		t.Fatalf("Go generation failed: %v", err)
	}

	if len(pyGroups) != len(goGroups) {
		t.Fatalf("Group count mismatch: python=%d, go=%d\npython: %+v\ngo: %+v",
			len(pyGroups), len(goGroups), pyGroups, goGroups)
	}

	for i := range pyGroups {
		pyTargets := strings.Join(pyGroups[i].Targets, ",")
		goTargets := strings.Join(goGroups[i].Targets, ",")
		if pyTargets != goTargets {
			t.Errorf("Group %d targets: python=%q, go=%q", i, pyTargets, goTargets)
		}

		for labelKey, pyVal := range pyGroups[i].Labels {
			goVal, ok := goGroups[i].Labels[labelKey]
			if !ok {
				t.Errorf("Group %d: label %q exists in python but not in go", i, labelKey)
			} else if pyVal != goVal {
				t.Errorf("Group %d label %q: python=%q, go=%q", i, labelKey, pyVal, goVal)
			}
		}
	}
}

// TestPythonGoTargetCompatibility_NodetoolStatus tests nodetool status parsing.
func TestPythonGoTargetCompatibility_NodetoolStatus(t *testing.T) {
	if !pythonAvailable(t) {
		t.Skip("python3 not available")
	}

	nodetoolOutput := `Datacenter: us-east-1
=====================
Status=Up/Down
|/ State=Normal/Leaving/Joining/Moving
--  Address       Load       Tokens  Owns    Host ID                               Rack
UN  10.0.0.1      256.0 KB   256     33.3%   aaa-bbb-ccc                           rack1
UN  10.0.0.2      512.0 KB   256     33.3%   ddd-eee-fff                           rack1
Datacenter: us-west-2
=====================
Status=Up/Down
|/ State=Normal/Leaving/Joining/Moving
--  Address       Load       Tokens  Owns    Host ID                               Rack
UN  10.0.1.1      128.0 KB   256     33.3%   ggg-hhh-iii                           rack1
`

	// Python: pipe nodetool output via stdin
	root := absRepoRoot(t)
	outDir := t.TempDir()
	scriptPath := filepath.Join(root, "genconfig.py")

	cmd := exec.Command("python3", scriptPath,
		"-d", outDir,
		"-c", "nodetool-cluster",
		"-o", "targets.yml",
		"-NS",
	)
	cmd.Dir = root
	cmd.Stdin = strings.NewReader(nodetoolOutput)
	output, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("Python genconfig.py failed: %v\noutput: %s", err, output)
	}

	pyData, err := os.ReadFile(filepath.Join(outDir, "targets.yml"))
	if err != nil {
		t.Fatalf("reading python output: %v", err)
	}

	var pyGroups []TargetGroup
	if err := yaml.Unmarshal(pyData, &pyGroups); err != nil {
		t.Fatalf("parsing python YAML: %v", err)
	}

	// Go: parse nodetool output
	servers, err := ParseNodetoolStatus(strings.NewReader(nodetoolOutput))
	if err != nil {
		t.Fatalf("Go ParseNodetoolStatus failed: %v", err)
	}

	goGroups, err := GenerateTargets(servers, "nodetool-cluster", "")
	if err != nil {
		t.Fatalf("Go GenerateTargets failed: %v", err)
	}

	if len(pyGroups) != len(goGroups) {
		t.Fatalf("Group count mismatch: python=%d, go=%d\npython: %+v\ngo: %+v",
			len(pyGroups), len(goGroups), pyGroups, goGroups)
	}

	for i := range pyGroups {
		if len(pyGroups[i].Targets) != len(goGroups[i].Targets) {
			t.Errorf("Group %d target count: python=%d, go=%d", i,
				len(pyGroups[i].Targets), len(goGroups[i].Targets))
			continue
		}
		for j := range pyGroups[i].Targets {
			if pyGroups[i].Targets[j] != goGroups[i].Targets[j] {
				t.Errorf("Group %d target %d: python=%q, go=%q",
					i, j, pyGroups[i].Targets[j], goGroups[i].Targets[j])
			}
		}
		if pyGroups[i].Labels["dc"] != goGroups[i].Labels["dc"] {
			t.Errorf("Group %d dc: python=%q, go=%q",
				i, pyGroups[i].Labels["dc"], goGroups[i].Labels["dc"])
		}
	}
}

// TestPythonGoTargetCompatibility_YAMLOutput tests that YAML serialization matches.
func TestPythonGoTargetCompatibility_YAMLOutput(t *testing.T) {
	if !pythonAvailable(t) {
		t.Skip("python3 not available")
	}

	dcs := []string{"dc1:10.0.0.1,10.0.0.2", "dc2:10.0.0.3"}
	cluster := "yaml-test"

	// Python output
	root := absRepoRoot(t)
	pyDir := t.TempDir()
	cmd := exec.Command("python3", filepath.Join(root, "genconfig.py"),
		"-d", pyDir, "-c", cluster, "-o", "targets.yml",
		"-dc", dcs[0], "-dc", dcs[1])
	cmd.Dir = root
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("Python failed: %v\n%s", err, out)
	}
	pyData, _ := os.ReadFile(filepath.Join(pyDir, "targets.yml"))

	// Go output
	goDir := t.TempDir()
	goGroups, err := GenerateTargets(dcs, cluster, "")
	if err != nil {
		t.Fatalf("Go failed: %v", err)
	}
	if err := WriteTargetsFile(goGroups, goDir, "targets.yml"); err != nil {
		t.Fatalf("Go WriteTargetsFile failed: %v", err)
	}
	goData, _ := os.ReadFile(filepath.Join(goDir, "targets.yml"))

	// Parse both and compare structurally
	var pyParsed, goParsed []TargetGroup
	yaml.Unmarshal(pyData, &pyParsed)
	yaml.Unmarshal(goData, &goParsed)

	if len(pyParsed) != len(goParsed) {
		t.Fatalf("Parsed group count: python=%d, go=%d\npython YAML:\n%s\ngo YAML:\n%s",
			len(pyParsed), len(goParsed), string(pyData), string(goData))
	}

	for i := range pyParsed {
		if len(pyParsed[i].Targets) != len(goParsed[i].Targets) {
			t.Errorf("Group %d target count: python=%d, go=%d", i,
				len(pyParsed[i].Targets), len(goParsed[i].Targets))
		}
	}

	t.Logf("Python YAML (%d bytes):\n%s", len(pyData), string(pyData))
	t.Logf("Go YAML (%d bytes):\n%s", len(goData), string(goData))
}
