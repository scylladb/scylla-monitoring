package dashboard

import (
	"testing"
)

func TestResolveType_Simple(t *testing.T) {
	types := map[string]interface{}{
		"base_row": map[string]interface{}{
			"collapse": false,
			"editable": true,
		},
	}
	result := ResolveType("base_row", types)
	if result["collapse"] != false {
		t.Errorf("expected collapse=false, got %v", result["collapse"])
	}
	if result["editable"] != true {
		t.Errorf("expected editable=true, got %v", result["editable"])
	}
}

func TestResolveType_Inheritance(t *testing.T) {
	types := map[string]interface{}{
		"base_row": map[string]interface{}{
			"collapse": false,
			"editable": true,
			"height":   "150px",
		},
		"small_row": map[string]interface{}{
			"class":  "base_row",
			"height": "25px",
		},
	}
	result := ResolveType("small_row", types)
	if result["height"] != "25px" {
		t.Errorf("expected height=25px (child override), got %v", result["height"])
	}
	if result["collapse"] != false {
		t.Errorf("expected collapse=false (inherited), got %v", result["collapse"])
	}
	if result["editable"] != true {
		t.Errorf("expected editable=true (inherited), got %v", result["editable"])
	}
}

func TestResolveType_DeepInheritance(t *testing.T) {
	types := map[string]interface{}{
		"base": map[string]interface{}{
			"a": "from_base",
			"b": "from_base",
		},
		"mid": map[string]interface{}{
			"class": "base",
			"b":     "from_mid",
			"c":     "from_mid",
		},
		"leaf": map[string]interface{}{
			"class": "mid",
			"c":     "from_leaf",
			"d":     "from_leaf",
		},
	}
	result := ResolveType("leaf", types)
	if result["a"] != "from_base" {
		t.Errorf("expected a=from_base, got %v", result["a"])
	}
	if result["b"] != "from_mid" {
		t.Errorf("expected b=from_mid, got %v", result["b"])
	}
	if result["c"] != "from_leaf" {
		t.Errorf("expected c=from_leaf, got %v", result["c"])
	}
	if result["d"] != "from_leaf" {
		t.Errorf("expected d=from_leaf, got %v", result["d"])
	}
}

func TestResolveType_Unknown(t *testing.T) {
	types := map[string]interface{}{}
	result := ResolveType("nonexistent", types)
	if len(result) != 0 {
		t.Errorf("expected empty map for unknown type, got %v", result)
	}
}

func TestResolveType_CircularDependency(t *testing.T) {
	types := map[string]interface{}{
		"a": map[string]interface{}{
			"class": "b",
			"x":     "from_a",
		},
		"b": map[string]interface{}{
			"class": "a",
			"y":     "from_b",
		},
	}
	// Should not stack overflow — cycle is broken by visited set
	result := ResolveType("a", types)
	if result["x"] != "from_a" {
		t.Errorf("expected x=from_a, got %v", result["x"])
	}
}

func TestResolveType_SelfReference(t *testing.T) {
	types := map[string]interface{}{
		"self": map[string]interface{}{
			"class": "self",
			"val":   "ok",
		},
	}
	result := ResolveType("self", types)
	if result["val"] != "ok" {
		t.Errorf("expected val=ok, got %v", result["val"])
	}
}

func TestUpdateObject_AutoID(t *testing.T) {
	obj := map[string]interface{}{
		"id":   "auto",
		"type": "panel",
	}
	id := 1
	result := UpdateObject(obj, map[string]interface{}{}, nil, nil, map[string]interface{}{}, &id)
	resultMap := result.(map[string]interface{})
	if resultMap["id"] != 1 {
		t.Errorf("expected id=1, got %v", resultMap["id"])
	}
	if id != 2 {
		t.Errorf("expected counter to be 2, got %d", id)
	}
}

func TestUpdateObject_ClassResolution(t *testing.T) {
	types := map[string]interface{}{
		"text_panel": map[string]interface{}{
			"type":     "text",
			"mode":     "markdown",
			"editable": true,
		},
	}
	obj := map[string]interface{}{
		"class":   "text_panel",
		"content": "hello",
		"id":      "auto",
	}
	id := 1
	result := UpdateObject(obj, types, nil, nil, map[string]interface{}{}, &id)
	resultMap := result.(map[string]interface{})
	if resultMap["type"] != "text" {
		t.Errorf("expected type=text from class, got %v", resultMap["type"])
	}
	if resultMap["content"] != "hello" {
		t.Errorf("expected content=hello, got %v", resultMap["content"])
	}
	if resultMap["id"] != 1 {
		t.Errorf("expected id=1, got %v", resultMap["id"])
	}
}

func TestUpdateObject_VersionReject(t *testing.T) {
	obj := map[string]interface{}{
		"type":        "panel",
		"dashversion": "6.0",
	}
	id := 1
	// Version 5.4 should reject dashversion 6.0
	result := UpdateObject(obj, map[string]interface{}{}, []int{5, 4}, nil, map[string]interface{}{}, &id)
	if result != nil {
		t.Error("expected nil (rejected), got non-nil")
	}
}

func TestUpdateObject_VersionAccept(t *testing.T) {
	obj := map[string]interface{}{
		"type":        "panel",
		"dashversion": "5.4",
	}
	id := 1
	result := UpdateObject(obj, map[string]interface{}{}, []int{5, 4}, nil, map[string]interface{}{}, &id)
	if result == nil {
		t.Error("expected non-nil (accepted), got nil")
	}
}

func TestUpdateObject_ArrayFiltering(t *testing.T) {
	obj := map[string]interface{}{
		"panels": []interface{}{
			map[string]interface{}{"type": "panel1", "dashversion": "5.4"},
			map[string]interface{}{"type": "panel2", "dashversion": "6.0"},
			map[string]interface{}{"type": "panel3"},
		},
	}
	id := 1
	result := UpdateObject(obj, map[string]interface{}{}, []int{5, 4}, nil, map[string]interface{}{}, &id)
	resultMap := result.(map[string]interface{})
	panels := resultMap["panels"].([]interface{})
	if len(panels) != 2 {
		t.Errorf("expected 2 panels after filtering, got %d", len(panels))
	}
}

func TestUpdateObject_ExactMatchReplace(t *testing.T) {
	obj := map[string]interface{}{
		"expr": "old_metric_name",
	}
	exactMatch := map[string]interface{}{
		"old_metric_name": "new_metric_name",
	}
	id := 1
	result := UpdateObject(obj, map[string]interface{}{}, nil, nil, exactMatch, &id)
	resultMap := result.(map[string]interface{})
	if resultMap["expr"] != "new_metric_name" {
		t.Errorf("expected expr=new_metric_name, got %v", resultMap["expr"])
	}
}

func TestUpdateObject_ProductReject(t *testing.T) {
	obj := map[string]interface{}{
		"type":        "panel",
		"dashproduct": "enterprise",
	}
	id := 1
	// No products specified, dashproduct is non-empty but not in products list
	result := UpdateObject(obj, map[string]interface{}{}, nil, nil, map[string]interface{}{}, &id)
	if result != nil {
		t.Error("expected nil (product rejected), got non-nil")
	}

	// Product matches
	obj2 := map[string]interface{}{
		"type":        "panel",
		"dashproduct": "enterprise",
	}
	id = 1
	result = UpdateObject(obj2, map[string]interface{}{}, nil, []string{"enterprise"}, map[string]interface{}{}, &id)
	if result == nil {
		t.Error("expected non-nil (product matches), got nil")
	}
}

func TestUpdateObject_ProductRejectField(t *testing.T) {
	obj := map[string]interface{}{
		"type":               "panel",
		"dashproductreject":  "enterprise",
	}
	id := 1
	result := UpdateObject(obj, map[string]interface{}{}, nil, []string{"enterprise"}, map[string]interface{}{}, &id)
	if result != nil {
		t.Error("expected nil (dashproductreject matched), got non-nil")
	}
}

func TestShouldProductReject(t *testing.T) {
	tests := []struct {
		name     string
		products []string
		obj      map[string]interface{}
		expected bool
	}{
		{
			"no dashproduct field",
			nil,
			map[string]interface{}{"type": "panel"},
			false,
		},
		{
			"empty dashproduct with no products",
			nil,
			map[string]interface{}{"dashproduct": ""},
			false,
		},
		{
			"empty dashproduct with products",
			[]string{"enterprise"},
			map[string]interface{}{"dashproduct": ""},
			true,
		},
		{
			"matching dashproduct",
			[]string{"enterprise"},
			map[string]interface{}{"dashproduct": "enterprise"},
			false,
		},
		{
			"non-matching dashproduct",
			[]string{"oss"},
			map[string]interface{}{"dashproduct": "enterprise"},
			true,
		},
		{
			"dashproductreject match",
			[]string{"enterprise"},
			map[string]interface{}{"dashproductreject": "enterprise"},
			true,
		},
		{
			"dashproductreject no match",
			[]string{"oss"},
			map[string]interface{}{"dashproductreject": "enterprise"},
			false,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := ShouldProductReject(tt.products, tt.obj)
			if result != tt.expected {
				t.Errorf("ShouldProductReject(%v, %v) = %v, want %v", tt.products, tt.obj, result, tt.expected)
			}
		})
	}
}
