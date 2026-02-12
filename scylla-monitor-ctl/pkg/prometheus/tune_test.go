package prometheus

import (
	"os"
	"strings"
	"testing"
)

func TestTuneConfig_DropMetrics(t *testing.T) {
	dir := t.TempDir()
	configPath := dir + "/prometheus.yml"
	original := `global:
  scrape_interval: 20s
  evaluation_interval: 20s
scrape_configs:
  - job_name: scylla
    # FILTER_METRICS
    file_sd_configs:
      - files:
        - /etc/prometheus/targets/scylla_servers.yml
`
	os.WriteFile(configPath, []byte(original), 0644)

	err := TuneConfig(TuneOptions{
		ConfigPath:  configPath,
		DropMetrics: []string{"cas", "cdc"},
	})
	if err != nil {
		t.Fatalf("TuneConfig: %v", err)
	}

	data, _ := os.ReadFile(configPath)
	config := string(data)
	if !strings.Contains(config, ".*_cas.*") {
		t.Error("expected cas drop rule")
	}
	if !strings.Contains(config, ".*_cdc_.*") {
		t.Error("expected cdc drop rule")
	}
}

func TestTuneConfig_KeepMetrics(t *testing.T) {
	dir := t.TempDir()
	configPath := dir + "/prometheus.yml"
	original := `global:
  scrape_interval: 20s
scrape_configs:
  - job_name: scylla
    # FILTER_METRICS
`
	os.WriteFile(configPath, []byte(original), 0644)

	err := TuneConfig(TuneOptions{
		ConfigPath:  configPath,
		DropMetrics: []string{"cas", "cache"},
		KeepMetrics: []string{"cache"},
	})
	if err != nil {
		t.Fatalf("TuneConfig: %v", err)
	}

	data, _ := os.ReadFile(configPath)
	config := string(data)
	if !strings.Contains(config, ".*_cas.*") {
		t.Error("expected cas drop rule")
	}
	if strings.Contains(config, ".*cache.*") {
		t.Error("cache should have been filtered out by keep-metrics")
	}
}

func TestTuneConfig_ScrapeInterval(t *testing.T) {
	dir := t.TempDir()
	configPath := dir + "/prometheus.yml"
	original := `global:
  scrape_interval: 20s
  scrape_timeout: 15s
  evaluation_interval: 20s
`
	os.WriteFile(configPath, []byte(original), 0644)

	err := TuneConfig(TuneOptions{
		ConfigPath:     configPath,
		ScrapeInterval: "30s",
	})
	if err != nil {
		t.Fatalf("TuneConfig: %v", err)
	}

	data, _ := os.ReadFile(configPath)
	config := string(data)
	if !strings.Contains(config, "scrape_interval: 30s") {
		t.Error("expected scrape_interval: 30s")
	}
	if !strings.Contains(config, "scrape_timeout: 25s") {
		t.Error("expected scrape_timeout: 25s")
	}
}

func TestTuneConfig_EvaluationInterval(t *testing.T) {
	dir := t.TempDir()
	configPath := dir + "/prometheus.yml"
	original := `global:
  scrape_interval: 20s
  evaluation_interval: 20s
`
	os.WriteFile(configPath, []byte(original), 0644)

	err := TuneConfig(TuneOptions{
		ConfigPath:         configPath,
		EvaluationInterval: "60s",
	})
	if err != nil {
		t.Fatalf("TuneConfig: %v", err)
	}

	data, _ := os.ReadFile(configPath)
	config := string(data)
	if !strings.Contains(config, "evaluation_interval: 60s") {
		t.Error("expected evaluation_interval: 60s")
	}
}

func TestTuneConfig_NativeHistogram(t *testing.T) {
	dir := t.TempDir()
	configPath := dir + "/prometheus.yml"
	original := `global:
  scrape_interval: 20s
`
	os.WriteFile(configPath, []byte(original), 0644)

	enable := true
	err := TuneConfig(TuneOptions{
		ConfigPath:      configPath,
		NativeHistogram: &enable,
	})
	if err != nil {
		t.Fatalf("TuneConfig: %v", err)
	}

	data, _ := os.ReadFile(configPath)
	config := string(data)
	if !strings.Contains(config, "scrape_native_histograms: true") {
		t.Error("expected scrape_native_histograms: true")
	}
}
