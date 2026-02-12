package dashboard

import "testing"

func TestParseVersion(t *testing.T) {
	tests := []struct {
		input    string
		expected []int
	}{
		{"5.4", []int{5, 4}},
		{"6.0", []int{6, 0}},
		{"2024.1", []int{2024, 1}},
		{"master", []int{MasterVersion}},
		{"5", []int{5}},
	}
	for _, tt := range tests {
		t.Run(tt.input, func(t *testing.T) {
			result := ParseVersion(tt.input)
			if len(result) != len(tt.expected) {
				t.Fatalf("expected %v, got %v", tt.expected, result)
			}
			for i, v := range tt.expected {
				if result[i] != v {
					t.Errorf("expected %v, got %v", tt.expected, result)
					break
				}
			}
		})
	}
}

func TestIsVersionBigger(t *testing.T) {
	tests := []struct {
		name       string
		version    []int
		cmpVersion string
		expected   bool
	}{
		// Exact match
		{"5.4 matches 5.4", []int{5, 4}, "5.4", true},
		{"6.0 matches 6.0", []int{6, 0}, "6.0", true},
		{"5.4 doesn't match 6.0", []int{5, 4}, "6.0", false},
		{"2024.1 matches 2024.1", []int{2024, 1}, "2024.1", true},

		// Greater than
		{"6.0 > 5.0", []int{6, 0}, ">5.0", true},
		{"5.4 > 5.0", []int{5, 4}, ">5.0", true},
		{"5.0 >= 5.0 (> means >=)", []int{5, 0}, ">5.0", true},
		{"4.0 not > 5.0", []int{4, 0}, ">5.0", false},
		{"2025.1 > 2024.1", []int{2025, 1}, ">2024.1", true},

		// Less than
		{"4.0 < 5.0", []int{4, 0}, "<5.0", true},
		{"5.0 not < 5.0", []int{5, 0}, "<5.0", false},
		{"6.0 not < 5.0", []int{6, 0}, "<5.0", false},
		{"2023.1 < 2024.1", []int{2023, 1}, "<2024.1", true},

		// Master version
		{"master matches >5.0", []int{MasterVersion}, ">5.0", true},
		{"master matches exact 5.4", []int{MasterVersion}, "5.4", false},

		// Type mismatch (OSS vs enterprise)
		{"5.4 vs 2024.1 (type mismatch)", []int{5, 4}, "2024.1", false},
		{"2024.1 vs 5.4 (type mismatch)", []int{2024, 1}, "5.4", false},

		// Edge cases
		{"5.4 vs >5.3", []int{5, 4}, ">5.3", true},
		{"5.4 vs <5.5", []int{5, 4}, "<5.5", true},
		{"5.4 vs <5.4", []int{5, 4}, "<5.4", false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := IsVersionBigger(tt.version, tt.cmpVersion)
			if result != tt.expected {
				t.Errorf("IsVersionBigger(%v, %q) = %v, want %v", tt.version, tt.cmpVersion, result, tt.expected)
			}
		})
	}
}

func TestShouldVersionReject(t *testing.T) {
	tests := []struct {
		name     string
		version  []int
		obj      map[string]interface{}
		expected bool
	}{
		{
			"no version, no reject",
			nil,
			map[string]interface{}{"dashversion": "5.0"},
			false,
		},
		{
			"no dashversion field",
			[]int{5, 4},
			map[string]interface{}{},
			false,
		},
		{
			"matching string version",
			[]int{5, 4},
			map[string]interface{}{"dashversion": "5.4"},
			false,
		},
		{
			"non-matching string version",
			[]int{5, 4},
			map[string]interface{}{"dashversion": "6.0"},
			true,
		},
		{
			"matching with > operator",
			[]int{6, 0},
			map[string]interface{}{"dashversion": ">5.0"},
			false,
		},
		{
			"list with one match",
			[]int{5, 4},
			map[string]interface{}{"dashversion": []interface{}{"5.4", "6.0"}},
			false,
		},
		{
			"list with no match",
			[]int{4, 0},
			map[string]interface{}{"dashversion": []interface{}{"5.4", "6.0"}},
			true,
		},
		{
			"list with > operator match",
			[]int{6, 0},
			map[string]interface{}{"dashversion": []interface{}{">5.0", "<4.0"}},
			false,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := ShouldVersionReject(tt.version, tt.obj)
			if result != tt.expected {
				t.Errorf("ShouldVersionReject(%v, %v) = %v, want %v", tt.version, tt.obj, result, tt.expected)
			}
		})
	}
}
