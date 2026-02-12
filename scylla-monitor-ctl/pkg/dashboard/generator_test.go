package dashboard

import (
	"encoding/json"
	"os"
	"testing"
)

func TestNewGenerator(t *testing.T) {
	typesData := []byte(`{
		"base_row": {
			"collapse": false,
			"editable": true
		},
		"small_row": {
			"class": "base_row",
			"height": "25px"
		}
	}`)

	g, err := NewGenerator(typesData)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(g.Types) != 2 {
		t.Errorf("expected 2 types, got %d", len(g.Types))
	}
}

func TestGenerator_Generate(t *testing.T) {
	typesData := []byte(`{
		"base_row": {
			"collapse": false,
			"editable": true,
			"height": "150px"
		},
		"text_panel": {
			"type": "text",
			"mode": "markdown",
			"editable": true
		}
	}`)

	templateData := []byte(`{
		"dashboard": {
			"title": "Test Dashboard",
			"rows": [
				{
					"class": "base_row",
					"panels": [
						{
							"class": "text_panel",
							"content": "Hello",
							"id": "auto",
							"span": 12
						}
					]
				}
			]
		}
	}`)

	g, err := NewGenerator(typesData)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	output, err := g.Generate(templateData)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	var result map[string]interface{}
	if err := json.Unmarshal(output, &result); err != nil {
		t.Fatalf("invalid JSON output: %v", err)
	}

	if result["title"] != "Test Dashboard" {
		t.Errorf("expected title 'Test Dashboard', got %v", result["title"])
	}

	panels, ok := result["panels"].([]interface{})
	if !ok {
		t.Fatal("expected panels array in output")
	}
	if len(panels) != 1 {
		t.Fatalf("expected 1 panel, got %d", len(panels))
	}

	p := panels[0].(map[string]interface{})
	if p["type"] != "text" {
		t.Errorf("expected type 'text' from class resolution, got %v", p["type"])
	}
	if p["content"] != "Hello" {
		t.Errorf("expected content 'Hello', got %v", p["content"])
	}
	// id should be auto-assigned to 1
	if id, ok := p["id"].(float64); !ok || int(id) != 1 {
		t.Errorf("expected id=1 from auto, got %v", p["id"])
	}
}

func TestGenerator_Replacements(t *testing.T) {
	typesData := []byte(`{}`)
	templateData := []byte(`{
		"dashboard": {
			"title": "__MONITOR_VERSION__",
			"version": "__SCYLLA_VERSION_DOT__",
			"rows": []
		}
	}`)

	g, err := NewGenerator(typesData)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	g.SetReplacements([][2]string{
		{"__MONITOR_VERSION__", "4.14"},
		{"__SCYLLA_VERSION_DOT__", "6.2"},
	})

	output, err := g.Generate(templateData)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	var result map[string]interface{}
	if err := json.Unmarshal(output, &result); err != nil {
		t.Fatalf("invalid JSON output: %v", err)
	}

	if result["title"] != "4.14" {
		t.Errorf("expected title '4.14', got %v", result["title"])
	}
	if result["version"] != "6.2" {
		t.Errorf("expected version '6.2', got %v", result["version"])
	}
}

func TestGenerator_DashedReplacement(t *testing.T) {
	typesData := []byte(`{}`)
	templateData := []byte(`{
		"dashboard": {
			"dotted": "__SCYLLA_VERSION_DOT__",
			"dashed": "__SCYLLA_VERSION_DASHED__",
			"rows": []
		}
	}`)

	g, err := NewGenerator(typesData)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	g.SetReplacements([][2]string{
		{"__SCYLLA_VERSION_DOT__", "6.2"},
	})

	output, err := g.Generate(templateData)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	s := string(output)
	if !contains(s, `"6.2"`) {
		t.Error("expected dotted version 6.2 in output")
	}
	if !contains(s, `"6-2"`) {
		t.Error("expected dashed version 6-2 in output")
	}
}

func contains(s, sub string) bool {
	return len(s) >= len(sub) && (s == sub || len(s) > 0 && containsHelper(s, sub))
}

func containsHelper(s, sub string) bool {
	for i := 0; i <= len(s)-len(sub); i++ {
		if s[i:i+len(sub)] == sub {
			return true
		}
	}
	return false
}

func TestGenerator_VersionFiltering(t *testing.T) {
	typesData := []byte(`{}`)
	templateData := []byte(`{
		"dashboard": {
			"title": "Test",
			"rows": [
				{
					"height": "150px",
					"panels": [
						{
							"type": "graph",
							"id": "auto",
							"dashversion": "5.4",
							"span": 6
						},
						{
							"type": "graph",
							"id": "auto",
							"dashversion": "6.0",
							"span": 6
						},
						{
							"type": "graph",
							"id": "auto",
							"span": 6
						}
					]
				}
			]
		}
	}`)

	g, err := NewGenerator(typesData)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	g.SetVersion("5.4")

	output, err := g.Generate(templateData)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	var result map[string]interface{}
	if err := json.Unmarshal(output, &result); err != nil {
		t.Fatalf("invalid JSON output: %v", err)
	}

	panels, ok := result["panels"].([]interface{})
	if !ok {
		t.Fatal("expected panels array")
	}
	// Should have 2 panels: dashversion "5.4" (match) and no dashversion
	// dashversion "6.0" should be rejected
	if len(panels) != 2 {
		t.Errorf("expected 2 panels after version filtering, got %d", len(panels))
	}
}

func TestParseReplacements(t *testing.T) {
	input := []string{"__A__=hello", "__B__=world", "__C__"}
	result := ParseReplacements(input)
	if len(result) != 3 {
		t.Fatalf("expected 3 replacements, got %d", len(result))
	}
	if result[0][0] != "__A__" || result[0][1] != "hello" {
		t.Errorf("unexpected first replacement: %v", result[0])
	}
	if result[2][0] != "__C__" || result[2][1] != "" {
		t.Errorf("unexpected third replacement: %v", result[2])
	}
}

func TestGenerator_GenerateToFile(t *testing.T) {
	typesData := []byte(`{}`)
	templateData := []byte(`{
		"dashboard": {
			"title": "File Test",
			"rows": []
		}
	}`)

	g, err := NewGenerator(typesData)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	tmpDir := t.TempDir()
	outputPath := tmpDir + "/test-dashboard.json"

	err = g.GenerateToFile(templateData, outputPath)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	data, err := os.ReadFile(outputPath)
	if err != nil {
		t.Fatalf("reading output: %v", err)
	}

	var result map[string]interface{}
	if err := json.Unmarshal(data, &result); err != nil {
		t.Fatalf("invalid JSON: %v", err)
	}
	if result["title"] != "File Test" {
		t.Errorf("expected title 'File Test', got %v", result["title"])
	}
}
