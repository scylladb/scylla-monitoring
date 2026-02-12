package dashboard

import (
	"regexp"
	"strconv"
)

var heightRe = regexp.MustCompile(`(\d+)`)

// getHeight extracts pixel height from a string like "150px" and converts to grid units (px/30).
func getHeight(value string, defaultH int) int {
	m := heightRe.FindStringSubmatch(value)
	if m != nil {
		px, err := strconv.Atoi(m[1])
		if err == nil {
			return px / 30
		}
	}
	return defaultH
}

// panelWidth returns the width of a panel based on gridPos or span.
func panelWidth(gridPos, panel map[string]interface{}) int {
	if w, ok := gridPos["w"]; ok {
		if wf, ok := w.(float64); ok {
			return int(wf)
		}
		if wi, ok := w.(int); ok {
			return wi
		}
	}
	if span, ok := panel["span"]; ok {
		if sf, ok := span.(float64); ok {
			return int(sf) * 2
		}
		if si, ok := span.(int); ok {
			return si * 2
		}
	}
	return 6
}

// setGridPos sets the gridPos on a panel, using provided coordinates and defaults.
func setGridPos(x, y int, panel map[string]interface{}, h int, gridPos map[string]interface{}) int {
	if _, ok := gridPos["x"]; !ok {
		gridPos["x"] = x
	}
	if _, ok := gridPos["y"]; !ok {
		gridPos["y"] = y
	}
	if _, ok := gridPos["h"]; !ok {
		if height, ok := panel["height"]; ok {
			if hs, ok := height.(string); ok {
				gridPos["h"] = getHeight(hs, h)
			} else {
				gridPos["h"] = h
			}
		} else {
			gridPos["h"] = h
		}
	}
	if _, ok := gridPos["w"]; !ok {
		gridPos["w"] = panelWidth(gridPos, panel)
	}
	panel["gridPos"] = gridPos

	if hv, ok := gridPos["h"]; ok {
		if hf, ok := hv.(float64); ok {
			return int(hf)
		}
		if hi, ok := hv.(int); ok {
			return hi
		}
	}
	return h
}

// addRow processes a row's panels and positions them on the grid.
func addRow(y int, panels *[]interface{}, row map[string]interface{}) int {
	h := 6
	x := 0
	maxH := 0

	if height, ok := row["height"]; ok {
		if hs, ok := height.(string); ok && hs != "auto" {
			h = getHeight(hs, h)
		}
	}
	if gp, ok := row["gridPos"].(map[string]interface{}); ok {
		if hv, ok := gp["h"]; ok {
			if hf, ok := hv.(float64); ok {
				h = int(hf)
			}
			if hi, ok := hv.(int); ok {
				h = hi
			}
		}
	}

	rowPanels, ok := row["panels"].([]interface{})
	if !ok {
		return y
	}

	for _, p := range rowPanels {
		pMap, ok := p.(map[string]interface{})
		if !ok {
			continue
		}

		var gridPos map[string]interface{}
		if gp, ok := pMap["gridPos"].(map[string]interface{}); ok {
			gridPos = copyMap(gp)
		} else {
			gridPos = map[string]interface{}{}
		}

		w := panelWidth(gridPos, pMap)
		if w+x > 24 {
			x = 0
			y = y + maxH
			maxH = 0
		}

		height := setGridPos(x, y, pMap, h, gridPos)
		x = x + w
		if height > maxH {
			maxH = height
		}

		*panels = append(*panels, pMap)
	}

	return y + maxH
}

// isCollapsedRow checks if a row has a single collapsed row panel.
func isCollapsedRow(row map[string]interface{}) bool {
	panels, ok := row["panels"].([]interface{})
	if !ok || len(panels) != 1 {
		return false
	}
	p, ok := panels[0].(map[string]interface{})
	if !ok {
		return false
	}
	pType, _ := p["type"].(string)
	collapsed, hasCollapsed := p["collapsed"]
	if pType == "row" && hasCollapsed {
		if cb, ok := collapsed.(bool); ok && cb {
			return true
		}
	}
	return false
}

// isCollapsableRow checks if a row has a single row-type panel.
func isCollapsableRow(row map[string]interface{}) bool {
	panels, ok := row["panels"].([]interface{})
	if !ok || len(panels) != 1 {
		return false
	}
	p, ok := panels[0].(map[string]interface{})
	if !ok {
		return false
	}
	pType, _ := p["type"].(string)
	return pType == "row"
}

// ConvertToGrafana5Layout converts a row-based dashboard to the Grafana 5+ panel-based layout.
func ConvertToGrafana5Layout(results map[string]interface{}) {
	dashboard, ok := results["dashboard"].(map[string]interface{})
	if !ok {
		return
	}

	rows, ok := dashboard["rows"].([]interface{})
	if !ok {
		return
	}

	var panels []interface{}
	y := 0
	inCollapsablePanel := false
	var collapsibleRow []interface{}
	var collapsiblePanels []interface{}

	for _, r := range rows {
		row, ok := r.(map[string]interface{})
		if !ok {
			continue
		}

		if isCollapsableRow(row) && inCollapsablePanel {
			// Finish previous collapsible section
			rowPanels, _ := collapsibleRow[0].(map[string]interface{})
			rowPanels["panels"] = collapsiblePanels
			panels = append(panels, collapsibleRow[0])
			collapsibleRow = nil
			collapsiblePanels = nil
			inCollapsablePanel = false
		}

		if isCollapsedRow(row) {
			inCollapsablePanel = true
			y = addRow(y, &collapsibleRow, row)
		} else {
			if inCollapsablePanel {
				y = addRow(y, &collapsiblePanels, row)
			} else {
				y = addRow(y, &panels, row)
			}
		}
	}

	delete(dashboard, "rows")

	if inCollapsablePanel && len(collapsibleRow) > 0 {
		rowPanels, _ := collapsibleRow[0].(map[string]interface{})
		rowPanels["panels"] = collapsiblePanels
		panels = append(panels, collapsibleRow[0])
	}

	dashboard["panels"] = panels
}
