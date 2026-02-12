package prometheus

import (
	"strings"
	"testing"
)

func TestCalculateTimeout(t *testing.T) {
	tests := []struct {
		interval string
		expected string
	}{
		{"20s", "15s"},
		{"30s", "25s"},
		{"10s", "5s"},
		{"5s", ""},
		{"1m", "55s"},
		{"2m", "115s"},
	}
	for _, tt := range tests {
		t.Run(tt.interval, func(t *testing.T) {
			result := calculateTimeout(tt.interval)
			if result != tt.expected {
				t.Errorf("calculateTimeout(%q) = %q, want %q", tt.interval, result, tt.expected)
			}
		})
	}
}

func TestGenerateConfig_BasicSubstitution(t *testing.T) {
	template := []byte(`global:
  scrape_interval: 20s
  scrape_timeout: 15s
  evaluation_interval: 20s

alerting:
  alertmanagers:
  - static_configs:
    - targets: ['AM_ADDRESS']

scrape_configs:
  - job_name: grafana
    static_configs:
    - targets: ['GRAFANA_ADDRESS']
`)

	opts := ConfigOptions{
		AlertManagerAddress: "aalert:9093",
		GrafanaAddress:      "agraf:3000",
	}

	result, err := GenerateConfig(template, opts)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	config := string(result)
	if !strings.Contains(config, "aalert:9093") {
		t.Error("expected AlertManager address substitution")
	}
	if !strings.Contains(config, "agraf:3000") {
		t.Error("expected Grafana address substitution")
	}
}

func TestGenerateConfig_MetricFiltering(t *testing.T) {
	template := []byte(`scrape_configs:
  - job_name: scylla
    metric_relabel_configs:
# FILTER_METRICS
`)

	opts := ConfigOptions{
		AlertManagerAddress: "aalert:9093",
		DropMetrics:         []string{"cas", "cdc"},
	}

	result, err := GenerateConfig(template, opts)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	config := string(result)
	if !strings.Contains(config, ".*_cas.*") {
		t.Error("expected CAS metric pattern in output")
	}
	if !strings.Contains(config, ".*_cdc_.*") {
		t.Error("expected CDC metric pattern in output")
	}
	if !strings.Contains(config, "action: drop") {
		t.Error("expected drop action in output")
	}
}

func TestGenerateConfig_ScrapeInterval(t *testing.T) {
	template := []byte(`global:
  scrape_interval: 20s
  scrape_timeout: 15s
  evaluation_interval: 20s
`)

	opts := ConfigOptions{
		AlertManagerAddress: "aalert:9093",
		ScrapeInterval:      "30s",
	}

	result, err := GenerateConfig(template, opts)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	config := string(result)
	if !strings.Contains(config, "scrape_interval: 30s") {
		t.Error("expected scrape_interval: 30s")
	}
	if !strings.Contains(config, "scrape_timeout: 25s") {
		t.Error("expected scrape_timeout: 25s")
	}
}

func TestGenerateConfig_NativeHistogram(t *testing.T) {
	template := []byte(`global:
  scrape_interval: 20s
`)

	opts := ConfigOptions{
		AlertManagerAddress: "aalert:9093",
		NativeHistogram:     true,
	}

	result, err := GenerateConfig(template, opts)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	config := string(result)
	if !strings.Contains(config, "scrape_native_histograms: true") {
		t.Error("expected scrape_native_histograms: true")
	}
}

func TestGenerateConfig_EvaluationInterval(t *testing.T) {
	template := []byte(`global:
  scrape_interval: 20s
  evaluation_interval: 20s
`)

	opts := ConfigOptions{
		AlertManagerAddress: "aalert:9093",
		EvaluationInterval:  "30s",
	}

	result, err := GenerateConfig(template, opts)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	config := string(result)
	if !strings.Contains(config, "evaluation_interval: 30s") {
		t.Error("expected evaluation_interval: 30s")
	}
}

func TestGenerateConfig_VectorSearch(t *testing.T) {
	template := []byte(`scrape_configs:
  - job_name: scylla
`)

	opts := ConfigOptions{
		AlertManagerAddress: "aalert:9093",
		VectorSearch:        true,
	}

	result, err := GenerateConfig(template, opts)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	config := string(result)
	if !strings.Contains(config, "job_name: vector_search") {
		t.Error("expected vector_search job")
	}
	if !strings.Contains(config, "job_name: vector_search_os") {
		t.Error("expected vector_search_os job")
	}
}
