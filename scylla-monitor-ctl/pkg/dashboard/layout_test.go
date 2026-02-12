package dashboard

import (
	"testing"
)

func TestGetHeight(t *testing.T) {
	tests := []struct {
		input    string
		expected int
	}{
		{"150px", 5},
		{"300px", 10},
		{"25px", 0},
		{"auto", 6},
		{"180px", 6},
	}
	for _, tt := range tests {
		t.Run(tt.input, func(t *testing.T) {
			result := getHeight(tt.input, 6)
			if result != tt.expected {
				t.Errorf("getHeight(%q, 6) = %d, want %d", tt.input, result, tt.expected)
			}
		})
	}
}

func TestPanelWidth(t *testing.T) {
	tests := []struct {
		name     string
		gridPos  map[string]interface{}
		panel    map[string]interface{}
		expected int
	}{
		{"from gridPos w", map[string]interface{}{"w": float64(12)}, map[string]interface{}{}, 12},
		{"from span", map[string]interface{}{}, map[string]interface{}{"span": float64(6)}, 12},
		{"default", map[string]interface{}{}, map[string]interface{}{}, 6},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := panelWidth(tt.gridPos, tt.panel)
			if result != tt.expected {
				t.Errorf("panelWidth() = %d, want %d", result, tt.expected)
			}
		})
	}
}

func TestConvertToGrafana5Layout_Simple(t *testing.T) {
	results := map[string]interface{}{
		"dashboard": map[string]interface{}{
			"rows": []interface{}{
				map[string]interface{}{
					"height": "150px",
					"panels": []interface{}{
						map[string]interface{}{
							"type": "graph",
							"span": float64(6),
						},
						map[string]interface{}{
							"type": "graph",
							"span": float64(6),
						},
					},
				},
			},
		},
	}

	ConvertToGrafana5Layout(results)

	dashboard := results["dashboard"].(map[string]interface{})
	if _, ok := dashboard["rows"]; ok {
		t.Error("expected rows to be removed")
	}
	panels, ok := dashboard["panels"].([]interface{})
	if !ok {
		t.Fatal("expected panels to be set")
	}
	if len(panels) != 2 {
		t.Fatalf("expected 2 panels, got %d", len(panels))
	}

	p0 := panels[0].(map[string]interface{})
	gp0 := p0["gridPos"].(map[string]interface{})
	if gp0["x"] != 0 {
		t.Errorf("expected panel 0 x=0, got %v", gp0["x"])
	}
	if gp0["y"] != 0 {
		t.Errorf("expected panel 0 y=0, got %v", gp0["y"])
	}
	if gp0["w"] != 12 {
		t.Errorf("expected panel 0 w=12, got %v", gp0["w"])
	}

	p1 := panels[1].(map[string]interface{})
	gp1 := p1["gridPos"].(map[string]interface{})
	if gp1["x"] != 12 {
		t.Errorf("expected panel 1 x=12, got %v", gp1["x"])
	}
}

func TestConvertToGrafana5Layout_RowWrap(t *testing.T) {
	results := map[string]interface{}{
		"dashboard": map[string]interface{}{
			"rows": []interface{}{
				map[string]interface{}{
					"height": "150px",
					"panels": []interface{}{
						map[string]interface{}{
							"type": "graph",
							"span": float64(12),
						},
						map[string]interface{}{
							"type": "graph",
							"span": float64(6),
						},
					},
				},
			},
		},
	}

	ConvertToGrafana5Layout(results)

	dashboard := results["dashboard"].(map[string]interface{})
	panels := dashboard["panels"].([]interface{})
	if len(panels) != 2 {
		t.Fatalf("expected 2 panels, got %d", len(panels))
	}

	// First panel takes full width (24 units because span 12 * 2)
	p0 := panels[0].(map[string]interface{})
	gp0 := p0["gridPos"].(map[string]interface{})
	if gp0["w"] != 24 {
		t.Errorf("expected panel 0 w=24, got %v", gp0["w"])
	}

	// Second panel wraps to next line
	p1 := panels[1].(map[string]interface{})
	gp1 := p1["gridPos"].(map[string]interface{})
	if gp1["x"] != 0 {
		t.Errorf("expected panel 1 x=0 (wrapped), got %v", gp1["x"])
	}
	if gp1["y"].(int) <= 0 {
		t.Errorf("expected panel 1 y > 0 (wrapped), got %v", gp1["y"])
	}
}

func TestConvertToGrafana5Layout_CollapsedRow(t *testing.T) {
	results := map[string]interface{}{
		"dashboard": map[string]interface{}{
			"rows": []interface{}{
				// A collapsed row panel
				map[string]interface{}{
					"panels": []interface{}{
						map[string]interface{}{
							"type":      "row",
							"collapsed": true,
							"title":     "Collapsed Section",
						},
					},
				},
				// Content inside collapsed section
				map[string]interface{}{
					"height": "150px",
					"panels": []interface{}{
						map[string]interface{}{
							"type": "graph",
							"span": float64(6),
						},
					},
				},
				// A new non-collapsed row
				map[string]interface{}{
					"panels": []interface{}{
						map[string]interface{}{
							"type":  "row",
							"title": "Regular Section",
						},
					},
				},
			},
		},
	}

	ConvertToGrafana5Layout(results)

	dashboard := results["dashboard"].(map[string]interface{})
	panels := dashboard["panels"].([]interface{})

	// Should have: 1 collapsible row (with nested panels) + 1 regular row panel
	if len(panels) < 2 {
		t.Fatalf("expected at least 2 panels, got %d", len(panels))
	}

	// First panel should be the collapsed row with nested panels
	p0 := panels[0].(map[string]interface{})
	if p0["type"] != "row" {
		t.Errorf("expected first panel to be row type, got %v", p0["type"])
	}
	nested, ok := p0["panels"].([]interface{})
	if !ok {
		t.Fatal("expected collapsed row to have nested panels")
	}
	if len(nested) != 1 {
		t.Errorf("expected 1 nested panel, got %d", len(nested))
	}
}
