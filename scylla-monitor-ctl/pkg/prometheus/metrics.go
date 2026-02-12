package prometheus

// MetricCategory represents a predefined group of metrics that can be dropped.
type MetricCategory struct {
	Name    string
	Pattern string
	Desc    string
}

// PredefinedCategories maps category names to their regex patterns.
var PredefinedCategories = map[string]MetricCategory{
	"cas":        {Name: "cas", Pattern: ".*_cas.*", Desc: "CAS (lightweight transactions)"},
	"cdc":        {Name: "cdc", Pattern: ".*_cdc_.*", Desc: "Change Data Capture"},
	"alternator": {Name: "alternator", Pattern: ".*alternator.*", Desc: "DynamoDB-compatible API"},
	"streaming":  {Name: "streaming", Pattern: ".*streaming.*", Desc: "Streaming operations"},
	"sstable":    {Name: "sstable", Pattern: ".*sstable.*", Desc: "SSTable-level metrics"},
	"cache":      {Name: "cache", Pattern: ".*cache.*", Desc: "Cache metrics"},
	"commitlog":  {Name: "commitlog", Pattern: ".*commitlog.*", Desc: "Commitlog metrics"},
	"compaction": {Name: "compaction", Pattern: ".*compaction.*", Desc: "Compaction metrics"},
}

// ResolveDropPatterns takes a list of category names and/or raw regex patterns
// and returns all resolved regex patterns for metric dropping.
func ResolveDropPatterns(names []string) []string {
	var patterns []string
	for _, name := range names {
		if cat, ok := PredefinedCategories[name]; ok {
			patterns = append(patterns, cat.Pattern)
		} else {
			// Treat as raw regex pattern
			patterns = append(patterns, name)
		}
	}
	return patterns
}

// GenerateDropRelabelConfig generates a metric_relabel_configs entry for dropping metrics.
func GenerateDropRelabelConfig(pattern string) map[string]interface{} {
	return map[string]interface{}{
		"source_labels": []string{"__name__"},
		"regex":         pattern,
		"action":        "drop",
	}
}

// GenerateDropRelabelConfigs generates all metric_relabel_configs entries for a list of patterns.
func GenerateDropRelabelConfigs(patterns []string) []map[string]interface{} {
	var configs []map[string]interface{}
	for _, p := range patterns {
		configs = append(configs, GenerateDropRelabelConfig(p))
	}
	return configs
}
