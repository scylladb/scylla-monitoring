package dashboard

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"sort"
	"strings"
	"testing"
)

// repo root relative to this test file
const relRepoRoot = "../../.."

func absRepoRoot(t *testing.T) string {
	t.Helper()
	abs, err := filepath.Abs(relRepoRoot)
	if err != nil {
		t.Fatalf("resolving repo root: %v", err)
	}
	return abs
}

// defaultDashboards is the standard set from dashboards.sh
var defaultDashboards = []string{
	"scylla-overview",
	"scylla-detailed",
	"scylla-os",
	"scylla-cql",
	"scylla-advanced",
	"alternator",
	"scylla-ks",
}

// testVersions to compare against Python
var testVersions = []string{"2025.3", "master"}

func pythonAvailable(t *testing.T) bool {
	t.Helper()
	_, err := exec.LookPath("python3")
	return err == nil
}

func metricsFileExists(t *testing.T) bool {
	t.Helper()
	root := absRepoRoot(t)
	_, err := os.Stat(filepath.Join(root, "docs/source/reference/metrics.yaml"))
	return err == nil
}

// generateWithPython runs make_dashboards.py and returns the generated JSON.
func generateWithPython(t *testing.T, dashboard, version string, useMetricsReplace bool) (map[string]interface{}, error) {
	t.Helper()

	root := absRepoRoot(t)
	outDir := t.TempDir()
	templatePath := filepath.Join(root, fmt.Sprintf("grafana/%s.template.json", dashboard))
	typesPath := filepath.Join(root, "grafana/types.json")
	scriptPath := filepath.Join(root, "make_dashboards.py")

	args := []string{
		scriptPath,
		"-af", outDir,
		"-t", typesPath,
		"-d", templatePath,
		"-R", "__MONITOR_VERSION__=master",
		"-R", fmt.Sprintf("__SCYLLA_VERSION_DOT__=%s", version),
		"-R", "__MONITOR_BRANCH_VERSION=master",
		"-R", "__REFRESH_INTERVAL__=5m",
		"-V", version,
	}

	if useMetricsReplace {
		metricsPath := filepath.Join(root, "docs/source/reference/metrics.yaml")
		args = append(args, "--replace-file", metricsPath)
	}

	cmd := exec.Command("python3", args...)
	cmd.Dir = root
	output, err := cmd.CombinedOutput()
	if err != nil {
		return nil, fmt.Errorf("python make_dashboards.py failed: %v\noutput: %s", err, string(output))
	}

	// Find the generated file
	pattern := filepath.Join(outDir, fmt.Sprintf("%s.*.json", dashboard))
	matches, err := filepath.Glob(pattern)
	if err != nil || len(matches) == 0 {
		// Try without version suffix
		pattern = filepath.Join(outDir, fmt.Sprintf("%s.json", dashboard))
		matches, _ = filepath.Glob(pattern)
		if len(matches) == 0 {
			// List what was actually generated
			entries, _ := os.ReadDir(outDir)
			var names []string
			for _, e := range entries {
				names = append(names, e.Name())
			}
			return nil, fmt.Errorf("no output file found matching %s.*.json in %s; files: %v", dashboard, outDir, names)
		}
	}

	data, err := os.ReadFile(matches[0])
	if err != nil {
		return nil, fmt.Errorf("reading python output: %v", err)
	}

	var result map[string]interface{}
	if err := json.Unmarshal(data, &result); err != nil {
		return nil, fmt.Errorf("parsing python JSON output: %v", err)
	}
	return result, nil
}

// generateWithGo runs the Go generator and returns the generated JSON.
func generateWithGo(t *testing.T, dashboard, version string, useMetricsReplace bool) (map[string]interface{}, error) {
	t.Helper()

	root := absRepoRoot(t)
	typesPath := filepath.Join(root, "grafana/types.json")
	templatePath := filepath.Join(root, fmt.Sprintf("grafana/%s.template.json", dashboard))

	typesData, err := os.ReadFile(typesPath)
	if err != nil {
		return nil, fmt.Errorf("reading types.json: %v", err)
	}

	templateData, err := os.ReadFile(templatePath)
	if err != nil {
		return nil, fmt.Errorf("reading template: %v", err)
	}

	gen, err := NewGenerator(typesData)
	if err != nil {
		return nil, fmt.Errorf("creating generator: %v", err)
	}

	gen.SetVersion(version)

	if useMetricsReplace {
		metricsPath := filepath.Join(root, "docs/source/reference/metrics.yaml")
		exactMatch, err := loadExactMatchYAML(metricsPath)
		if err != nil {
			return nil, fmt.Errorf("loading metrics.yaml: %v", err)
		}
		gen.ExactMatch = exactMatch
	}

	gen.SetReplacements([][2]string{
		{"__MONITOR_VERSION__", "master"},
		{"__SCYLLA_VERSION_DOT__", version},
		{"__MONITOR_BRANCH_VERSION", "master"},
		{"__REFRESH_INTERVAL__", "5m"},
	})

	output, err := gen.Generate(templateData)
	if err != nil {
		return nil, fmt.Errorf("generating: %v", err)
	}

	var result map[string]interface{}
	if err := json.Unmarshal(output, &result); err != nil {
		return nil, fmt.Errorf("parsing go JSON output: %v", err)
	}
	return result, nil
}

// generateWithGoRaw runs the Go generator and returns the raw JSON bytes (not re-serialized).
func generateWithGoRaw(t *testing.T, dashboard, version string, useMetricsReplace bool) ([]byte, error) {
	t.Helper()

	root := absRepoRoot(t)
	typesPath := filepath.Join(root, "grafana/types.json")
	templatePath := filepath.Join(root, fmt.Sprintf("grafana/%s.template.json", dashboard))

	typesData, err := os.ReadFile(typesPath)
	if err != nil {
		return nil, fmt.Errorf("reading types.json: %v", err)
	}

	templateData, err := os.ReadFile(templatePath)
	if err != nil {
		return nil, fmt.Errorf("reading template: %v", err)
	}

	gen, err := NewGenerator(typesData)
	if err != nil {
		return nil, fmt.Errorf("creating generator: %v", err)
	}

	gen.SetVersion(version)

	if useMetricsReplace {
		metricsPath := filepath.Join(root, "docs/source/reference/metrics.yaml")
		exactMatch, err := loadExactMatchYAML(metricsPath)
		if err != nil {
			return nil, fmt.Errorf("loading metrics.yaml: %v", err)
		}
		gen.ExactMatch = exactMatch
	}

	gen.SetReplacements([][2]string{
		{"__MONITOR_VERSION__", "master"},
		{"__SCYLLA_VERSION_DOT__", version},
		{"__MONITOR_BRANCH_VERSION", "master"},
		{"__REFRESH_INTERVAL__", "5m"},
	})

	return gen.Generate(templateData)
}

// loadExactMatchYAML loads a YAML file into a map[string]interface{} for exact-match replacement.
func loadExactMatchYAML(path string) (map[string]interface{}, error) {
	// Shell out to python to convert YAML to JSON
	cmd := exec.Command("python3", "-c",
		"import yaml, json, sys; print(json.dumps(yaml.safe_load(open(sys.argv[1]))))", path)
	out, err := cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("converting yaml to json: %v", err)
	}
	var result map[string]interface{}
	if err := json.Unmarshal(out, &result); err != nil {
		return nil, fmt.Errorf("parsing converted yaml: %v", err)
	}
	return result, nil
}

// TestPythonGoCompatibility_AllDashboards is the full integration test.
// It generates each default dashboard with both Python and Go, then compares.
func TestPythonGoCompatibility_AllDashboards(t *testing.T) {
	if !pythonAvailable(t) {
		t.Skip("python3 not available")
	}

	useMetrics := metricsFileExists(t)

	for _, version := range testVersions {
		for _, dashboard := range defaultDashboards {
			t.Run(fmt.Sprintf("%s/%s", dashboard, version), func(t *testing.T) {
				root := absRepoRoot(t)
				templatePath := filepath.Join(root, fmt.Sprintf("grafana/%s.template.json", dashboard))
				if _, err := os.Stat(templatePath); os.IsNotExist(err) {
					t.Skipf("template %s not found", templatePath)
				}

				pyResult, err := generateWithPython(t, dashboard, version, useMetrics)
				if err != nil {
					t.Fatalf("Python generation failed: %v", err)
				}

				goResult, err := generateWithGo(t, dashboard, version, useMetrics)
				if err != nil {
					t.Fatalf("Go generation failed: %v", err)
				}

				diffs := deepCompare("", pyResult, goResult)
				if len(diffs) > 0 {
					// Report first 20 diffs
					limit := 20
					if len(diffs) < limit {
						limit = len(diffs)
					}
					t.Errorf("Found %d differences between Python and Go output:", len(diffs))
					for i := 0; i < limit; i++ {
						t.Errorf("  %s", diffs[i])
					}
					if len(diffs) > limit {
						t.Errorf("  ... and %d more", len(diffs)-limit)
					}

					// Write both outputs for manual inspection
					pyJSON, _ := json.MarshalIndent(pyResult, "", "    ")
					goJSON, _ := json.MarshalIndent(goResult, "", "    ")
					debugDir := filepath.Join("../../testdata/debug", version)
					os.MkdirAll(debugDir, 0755)
					os.WriteFile(filepath.Join(debugDir, dashboard+".python.json"), pyJSON, 0644)
					os.WriteFile(filepath.Join(debugDir, dashboard+".go.json"), goJSON, 0644)
					t.Logf("Debug files written to testdata/debug/%s/", version)
				}
			})
		}
	}
}

// TestPythonGoCompatibility_ManagerDashboard tests the manager dashboard.
func TestPythonGoCompatibility_ManagerDashboard(t *testing.T) {
	if !pythonAvailable(t) {
		t.Skip("python3 not available")
	}

	root := absRepoRoot(t)
	templatePath := filepath.Join(root, "grafana/scylla-manager.template.json")
	if _, err := os.Stat(templatePath); os.IsNotExist(err) {
		t.Skip("manager template not found")
	}

	useMetrics := metricsFileExists(t)

	pyResult, err := generateWithPython(t, "scylla-manager", "3", useMetrics)
	if err != nil {
		t.Fatalf("Python generation failed: %v", err)
	}

	goResult, err := generateWithGo(t, "scylla-manager", "3", useMetrics)
	if err != nil {
		t.Fatalf("Go generation failed: %v", err)
	}

	diffs := deepCompare("", pyResult, goResult)
	if len(diffs) > 0 {
		limit := 20
		if len(diffs) < limit {
			limit = len(diffs)
		}
		t.Errorf("Found %d differences between Python and Go output:", len(diffs))
		for i := 0; i < limit; i++ {
			t.Errorf("  %s", diffs[i])
		}
	}
}

// deepCompare recursively compares two JSON-like structures and returns differences.
func deepCompare(path string, a, b interface{}) []string {
	var diffs []string

	if a == nil && b == nil {
		return nil
	}
	if a == nil || b == nil {
		return []string{fmt.Sprintf("%s: one is nil (python=%v, go=%v)", path, a, b)}
	}

	switch av := a.(type) {
	case map[string]interface{}:
		bv, ok := b.(map[string]interface{})
		if !ok {
			return []string{fmt.Sprintf("%s: type mismatch (python=map, go=%T)", path, b)}
		}
		// Collect all keys
		allKeys := map[string]bool{}
		for k := range av {
			allKeys[k] = true
		}
		for k := range bv {
			allKeys[k] = true
		}
		sortedKeys := make([]string, 0, len(allKeys))
		for k := range allKeys {
			sortedKeys = append(sortedKeys, k)
		}
		sort.Strings(sortedKeys)

		for _, k := range sortedKeys {
			aVal, aHas := av[k]
			bVal, bHas := bv[k]
			subPath := path + "." + k
			if path == "" {
				subPath = k
			}
			if !aHas {
				diffs = append(diffs, fmt.Sprintf("%s: only in Go (value=%v)", subPath, summarize(bVal)))
			} else if !bHas {
				diffs = append(diffs, fmt.Sprintf("%s: only in Python (value=%v)", subPath, summarize(aVal)))
			} else {
				diffs = append(diffs, deepCompare(subPath, aVal, bVal)...)
			}
		}

	case []interface{}:
		bv, ok := b.([]interface{})
		if !ok {
			return []string{fmt.Sprintf("%s: type mismatch (python=array[%d], go=%T)", path, len(av), b)}
		}
		if len(av) != len(bv) {
			diffs = append(diffs, fmt.Sprintf("%s: array length mismatch (python=%d, go=%d)", path, len(av), len(bv)))
			// Compare up to the shorter length
			minLen := len(av)
			if len(bv) < minLen {
				minLen = len(bv)
			}
			for i := 0; i < minLen; i++ {
				diffs = append(diffs, deepCompare(fmt.Sprintf("%s[%d]", path, i), av[i], bv[i])...)
			}
		} else {
			for i := 0; i < len(av); i++ {
				diffs = append(diffs, deepCompare(fmt.Sprintf("%s[%d]", path, i), av[i], bv[i])...)
			}
		}

	case float64:
		if !numericEqual(av, b) {
			diffs = append(diffs, fmt.Sprintf("%s: value mismatch (python=%v, go=%v)", path, a, b))
		}

	case string:
		bStr, ok := b.(string)
		if !ok {
			diffs = append(diffs, fmt.Sprintf("%s: type mismatch (python=string, go=%T)", path, b))
		} else if av != bStr {
			diffs = append(diffs, fmt.Sprintf("%s: string mismatch (python=%q, go=%q)", path, truncate(av, 80), truncate(bStr, 80)))
		}

	case bool:
		bBool, ok := b.(bool)
		if !ok {
			diffs = append(diffs, fmt.Sprintf("%s: type mismatch (python=bool, go=%T)", path, b))
		} else if av != bBool {
			diffs = append(diffs, fmt.Sprintf("%s: bool mismatch (python=%v, go=%v)", path, av, bBool))
		}

	default:
		if !reflect.DeepEqual(a, b) {
			diffs = append(diffs, fmt.Sprintf("%s: value mismatch (python=%v, go=%v)", path, a, b))
		}
	}

	return diffs
}

func numericEqual(a float64, b interface{}) bool {
	switch bv := b.(type) {
	case float64:
		return a == bv
	case int:
		return a == float64(bv)
	case int64:
		return a == float64(bv)
	}
	return false
}

func summarize(v interface{}) string {
	switch vv := v.(type) {
	case map[string]interface{}:
		return fmt.Sprintf("map[%d keys]", len(vv))
	case []interface{}:
		return fmt.Sprintf("array[%d]", len(vv))
	case string:
		return truncate(vv, 60)
	default:
		s := fmt.Sprintf("%v", v)
		return truncate(s, 60)
	}
}

func truncate(s string, max int) string {
	if len(s) > max {
		return s[:max] + "..."
	}
	return s
}

// TestPythonGoCompatibility_ByteForByte checks if JSON serialization matches exactly.
func TestPythonGoCompatibility_ByteForByte(t *testing.T) {
	if !pythonAvailable(t) {
		t.Skip("python3 not available")
	}

	// Test with a single small dashboard for byte-level comparison
	root := absRepoRoot(t)
	dashboard := "scylla-overview"
	version := "2025.3"

	templatePath := filepath.Join(root, fmt.Sprintf("grafana/%s.template.json", dashboard))
	if _, err := os.Stat(templatePath); os.IsNotExist(err) {
		t.Skip("template not found")
	}

	useMetrics := metricsFileExists(t)

	// Generate with Python — get raw bytes
	outDir := t.TempDir()
	typesPath := filepath.Join(root, "grafana/types.json")
	scriptPath := filepath.Join(root, "make_dashboards.py")

	args := []string{
		scriptPath,
		"-af", outDir,
		"-t", typesPath,
		"-d", templatePath,
		"-R", "__MONITOR_VERSION__=master",
		"-R", fmt.Sprintf("__SCYLLA_VERSION_DOT__=%s", version),
		"-R", "__MONITOR_BRANCH_VERSION=master",
		"-R", "__REFRESH_INTERVAL__=5m",
		"-V", version,
	}
	if useMetrics {
		args = append(args, "--replace-file", filepath.Join(root, "docs/source/reference/metrics.yaml"))
	}

	cmd := exec.Command("python3", args...)
	cmd.Dir = root
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("Python failed: %v\n%s", err, out)
	}

	matches, _ := filepath.Glob(filepath.Join(outDir, "*.json"))
	if len(matches) == 0 {
		t.Fatal("No Python output file")
	}
	pyBytes, _ := os.ReadFile(matches[0])

	// Generate with Go — get raw bytes directly from the generator
	goBytes, err := generateWithGoRaw(t, dashboard, version, useMetrics)
	if err != nil {
		t.Fatalf("Go failed: %v", err)
	}

	pyLines := strings.Split(string(pyBytes), "\n")
	goLines := strings.Split(string(goBytes), "\n")

	// Compare line by line
	maxLines := len(pyLines)
	if len(goLines) > maxLines {
		maxLines = len(goLines)
	}

	diffCount := 0
	for i := 0; i < maxLines; i++ {
		var pyLine, goLine string
		if i < len(pyLines) {
			pyLine = pyLines[i]
		}
		if i < len(goLines) {
			goLine = goLines[i]
		}
		if pyLine != goLine {
			diffCount++
			if diffCount <= 10 {
				t.Errorf("Line %d differs:\n  python: %s\n  go:     %s", i+1, truncate(pyLine, 120), truncate(goLine, 120))
			}
		}
	}

	if diffCount > 0 {
		t.Errorf("Total line differences: %d out of %d lines (python=%d lines, go=%d lines)",
			diffCount, maxLines, len(pyLines), len(goLines))

		// Save for manual diff
		debugDir := "../../testdata/debug/byte_compare"
		os.MkdirAll(debugDir, 0755)
		os.WriteFile(filepath.Join(debugDir, "python.json"), pyBytes, 0644)
		os.WriteFile(filepath.Join(debugDir, "go.json"), goBytes, 0644)
		t.Logf("Files saved to testdata/debug/byte_compare/ for manual diff")
	} else {
		t.Logf("Byte-for-byte match! (%d lines)", len(pyLines))
	}
}
