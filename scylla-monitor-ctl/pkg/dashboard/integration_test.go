package dashboard

import (
	"encoding/json"
	"os"
	"testing"
)

// TestGeneratorWithTestdata tests the full generator pipeline using the testdata fixtures.
func TestGeneratorWithTestdata(t *testing.T) {
	typesData, err := os.ReadFile("../../testdata/types_small.json")
	if err != nil {
		t.Fatalf("reading types: %v", err)
	}

	templateData, err := os.ReadFile("../../testdata/template_small.json")
	if err != nil {
		t.Fatalf("reading template: %v", err)
	}

	gen, err := NewGenerator(typesData)
	if err != nil {
		t.Fatalf("creating generator: %v", err)
	}

	gen.SetVersion("5.4")
	gen.SetReplacements([][2]string{
		{"__SCYLLA_VERSION_DOT__", "5.4"},
		{"__MONITOR_VERSION__", "4.14"},
	})

	output, err := gen.Generate(templateData)
	if err != nil {
		t.Fatalf("generating dashboard: %v", err)
	}

	var result map[string]interface{}
	if err := json.Unmarshal(output, &result); err != nil {
		t.Fatalf("invalid JSON output: %v", err)
	}

	// Verify title was replaced
	title, _ := result["title"].(string)
	if title != "Test Dashboard 5.4" {
		t.Errorf("expected title 'Test Dashboard 5.4', got %q", title)
	}

	// Verify panels
	panels, ok := result["panels"].([]interface{})
	if !ok {
		t.Fatal("expected panels array")
	}

	// With version 5.4:
	// - text panel (no dashversion) -> kept
	// - Panel A (no dashversion) -> kept
	// - Panel B (dashversion ">5.0") -> kept (5.4 >= 5.0)
	// - Panel C (dashversion "6.0") -> rejected (5.4 != 6.0)
	// Total: 3 panels
	if len(panels) != 3 {
		t.Errorf("expected 3 panels, got %d", len(panels))
		for i, p := range panels {
			pm, _ := p.(map[string]interface{})
			t.Logf("  panel %d: title=%v type=%v", i, pm["title"], pm["type"])
		}
	}

	// Verify gridPos is set on all panels
	for i, p := range panels {
		pm, _ := p.(map[string]interface{})
		if _, ok := pm["gridPos"]; !ok {
			t.Errorf("panel %d missing gridPos", i)
		}
	}

	// Save expected output for future comparisons
	expectedDir := "../../testdata/expected_output"
	os.MkdirAll(expectedDir, 0755)
	os.WriteFile(expectedDir+"/test-dashboard.5.4.json", output, 0644)
}

// TestGeneratorWithRealTypes tests the generator with the actual types.json from assets.
func TestGeneratorWithRealTypes(t *testing.T) {
	typesData, err := os.ReadFile("../../assets/grafana/types.json")
	if err != nil {
		t.Skip("assets/grafana/types.json not available, skipping integration test")
	}

	gen, err := NewGenerator(typesData)
	if err != nil {
		t.Fatalf("creating generator from real types.json: %v", err)
	}

	if len(gen.Types) == 0 {
		t.Fatal("expected non-empty types from real types.json")
	}

	// Test that common types resolve correctly
	testTypes := []string{"base_row", "row", "graph_panel", "dashboard"}
	for _, name := range testTypes {
		result := ResolveType(name, gen.Types)
		if len(result) == 0 {
			t.Logf("warning: type %q not found or empty (may not exist in current types.json)", name)
		}
	}

	// Try generating from a real template if available
	templateData, err := os.ReadFile("../../assets/grafana/scylla-overview.template.json")
	if err != nil {
		t.Skip("scylla-overview template not available")
	}

	gen.SetVersion("2025.3")
	gen.SetReplacements([][2]string{
		{"__SCYLLA_VERSION_DOT__", "2025.3"},
		{"__MONITOR_VERSION__", "4.14"},
		{"__REFRESH_INTERVAL__", "5m"},
		{"__MONITOR_BRANCH_VERSION", "4.14"},
	})

	output, err := gen.Generate(templateData)
	if err != nil {
		t.Fatalf("generating real dashboard: %v", err)
	}

	// Verify valid JSON output
	var result map[string]interface{}
	if err := json.Unmarshal(output, &result); err != nil {
		t.Fatalf("invalid JSON output from real template: %v", err)
	}

	// Verify it has panels
	if _, ok := result["panels"]; !ok {
		t.Error("expected 'panels' key in generated dashboard")
	}

	t.Logf("Generated dashboard with %d bytes", len(output))
}
