package prometheus

import (
	"testing"
)

func TestPredefinedCategories(t *testing.T) {
	expectedCategories := []string{"cas", "cdc", "alternator", "streaming", "sstable", "cache", "commitlog", "compaction"}
	for _, name := range expectedCategories {
		cat, ok := PredefinedCategories[name]
		if !ok {
			t.Errorf("expected category %q to exist", name)
			continue
		}
		if cat.Pattern == "" {
			t.Errorf("expected non-empty pattern for %q", name)
		}
		if cat.Desc == "" {
			t.Errorf("expected non-empty description for %q", name)
		}
	}
}

func TestResolveDropPatterns(t *testing.T) {
	tests := []struct {
		name     string
		input    []string
		expected []string
	}{
		{
			"single category",
			[]string{"cas"},
			[]string{".*_cas.*"},
		},
		{
			"multiple categories",
			[]string{"cas", "cdc"},
			[]string{".*_cas.*", ".*_cdc_.*"},
		},
		{
			"custom regex",
			[]string{"my_custom_metric_.*"},
			[]string{"my_custom_metric_.*"},
		},
		{
			"mixed",
			[]string{"cas", "my_custom_.*"},
			[]string{".*_cas.*", "my_custom_.*"},
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := ResolveDropPatterns(tt.input)
			if len(result) != len(tt.expected) {
				t.Fatalf("expected %d patterns, got %d", len(tt.expected), len(result))
			}
			for i, p := range tt.expected {
				if result[i] != p {
					t.Errorf("expected pattern %d = %q, got %q", i, p, result[i])
				}
			}
		})
	}
}

func TestGenerateDropRelabelConfig(t *testing.T) {
	config := GenerateDropRelabelConfig(".*_cas.*")
	if config["action"] != "drop" {
		t.Errorf("expected action=drop, got %v", config["action"])
	}
	if config["regex"] != ".*_cas.*" {
		t.Errorf("expected regex=.*_cas.*, got %v", config["regex"])
	}
	labels, ok := config["source_labels"].([]string)
	if !ok || len(labels) != 1 || labels[0] != "__name__" {
		t.Errorf("expected source_labels=[__name__], got %v", config["source_labels"])
	}
}

func TestGenerateDropRelabelConfigs(t *testing.T) {
	patterns := []string{".*_cas.*", ".*_cdc_.*"}
	configs := GenerateDropRelabelConfigs(patterns)
	if len(configs) != 2 {
		t.Fatalf("expected 2 configs, got %d", len(configs))
	}
	if configs[0]["regex"] != ".*_cas.*" {
		t.Errorf("expected first regex to be .*_cas.*, got %v", configs[0]["regex"])
	}
	if configs[1]["regex"] != ".*_cdc_.*" {
		t.Errorf("expected second regex to be .*_cdc_.*, got %v", configs[1]["regex"])
	}
}
