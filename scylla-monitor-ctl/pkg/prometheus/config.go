package prometheus

import (
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
)

// ConfigOptions holds all options for generating a prometheus.yml file.
type ConfigOptions struct {
	AlertManagerAddress  string
	GrafanaAddress       string
	ManagerAddress       string // For consul-based SD
	UseConsul            bool
	DropMetrics          []string // Category names or regex patterns
	ScrapeInterval       string   // e.g. "30s"
	EvaluationInterval   string   // e.g. "30s"
	NativeHistogram      bool
	NoNodeExporterFile   bool
	NoManagerAgentFile   bool
	VectorSearch         bool
	AdditionalTargets    []string // Paths to additional target files
	OutputPath           string
}

// GenerateConfig generates a prometheus.yml from a template with the given options.
func GenerateConfig(template []byte, opts ConfigOptions) ([]byte, error) {
	config := string(template)

	// Substitute placeholders
	config = strings.ReplaceAll(config, "AM_ADDRESS", opts.AlertManagerAddress)
	if opts.GrafanaAddress != "" {
		config = strings.ReplaceAll(config, "GRAFANA_ADDRESS", opts.GrafanaAddress)
	} else {
		config = strings.ReplaceAll(config, "GRAFANA_ADDRESS", "agraf:3000")
	}

	if opts.ManagerAddress != "" {
		config = strings.ReplaceAll(config, "MANAGER_ADDRESS", opts.ManagerAddress)
	}

	// Handle metric filtering
	if len(opts.DropMetrics) > 0 {
		patterns := ResolveDropPatterns(opts.DropMetrics)
		var filterLines []string
		for _, p := range patterns {
			filterLines = append(filterLines,
				"    - source_labels: [__name__]",
				"      regex: '"+p+"'",
				"      action: drop",
			)
		}
		filterBlock := strings.Join(filterLines, "\n")
		config = strings.ReplaceAll(config, "# FILTER_METRICS", filterBlock)
	} else {
		config = strings.ReplaceAll(config, "# FILTER_METRICS", "")
	}

	// Handle scrape interval
	if opts.ScrapeInterval != "" {
		config = replaceScrapeInterval(config, opts.ScrapeInterval)
	}

	// Handle evaluation interval
	if opts.EvaluationInterval != "" {
		config = replaceEvaluationInterval(config, opts.EvaluationInterval)
	}

	// Handle native histogram
	if opts.NativeHistogram {
		config = addNativeHistogram(config)
	}

	// Handle node exporter port mapping
	if opts.NoNodeExporterFile {
		config = addNodeExporterRelabel(config)
	}

	// Handle manager agent port mapping
	if opts.NoManagerAgentFile {
		config = addManagerAgentRelabel(config)
	}

	// Handle vector search jobs
	if opts.VectorSearch {
		config = addVectorSearchJobs(config)
	}

	// Append additional target files
	for _, tf := range opts.AdditionalTargets {
		data, err := os.ReadFile(tf)
		if err != nil {
			return nil, fmt.Errorf("reading additional target file %s: %w", tf, err)
		}
		config += "\n" + string(data)
	}

	return []byte(config), nil
}

// WriteConfig generates config and writes it to a file.
func WriteConfig(template []byte, opts ConfigOptions) error {
	data, err := GenerateConfig(template, opts)
	if err != nil {
		return err
	}

	dir := filepath.Dir(opts.OutputPath)
	if err := os.MkdirAll(dir, 0755); err != nil {
		return fmt.Errorf("creating output directory: %w", err)
	}

	if err := os.WriteFile(opts.OutputPath, data, 0644); err != nil {
		return fmt.Errorf("writing config: %w", err)
	}

	return nil
}

func replaceScrapeInterval(config, interval string) string {
	// Calculate timeout = interval - 5s
	timeout := calculateTimeout(interval)
	config = strings.Replace(config, "scrape_interval: 20s", "scrape_interval: "+interval, 1)
	if timeout != "" {
		config = strings.Replace(config, "scrape_timeout: 15s", "scrape_timeout: "+timeout, 1)
	}
	return config
}

func replaceEvaluationInterval(config, interval string) string {
	config = strings.Replace(config, "evaluation_interval: 20s", "evaluation_interval: "+interval, 1)
	return config
}

func addNativeHistogram(config string) string {
	// Add scrape_native_histograms: true to global config
	config = strings.Replace(config, "scrape_interval:", "scrape_native_histograms: true\n  scrape_interval:", 1)
	return config
}

func addNodeExporterRelabel(config string) string {
	relabel := `
    metric_relabel_configs:
    - source_labels: [__address__]
      regex: '(.*):\d+'
      target_label: __address__
      replacement: '${1}:9100'`
	config = strings.Replace(config, "# NODE_EXPORTER_RELABEL", relabel, 1)
	return config
}

func addManagerAgentRelabel(config string) string {
	relabel := `
    metric_relabel_configs:
    - source_labels: [__address__]
      regex: '(.*):\d+'
      target_label: __address__
      replacement: '${1}:5090'`
	config = strings.Replace(config, "# MANAGER_AGENT_RELABEL", relabel, 1)
	return config
}

func addVectorSearchJobs(config string) string {
	jobs := `

  - job_name: vector_search
    honor_labels: false
    file_sd_configs:
      - files:
        - /etc/prometheus/targets/vector_search_servers.yml
    metric_relabel_configs:
    - source_labels: [__address__]
      regex: '(.*):\d+'
      target_label: instance
      replacement: '${1}'
  - job_name: vector_search_os
    honor_labels: false
    file_sd_configs:
      - files:
        - /etc/prometheus/targets/vector_search_servers.yml
    relabel_configs:
    - source_labels: [__address__]
      regex: '(.*):\d+'
      target_label: __address__
      replacement: '${1}:9100'
    - source_labels: [__address__]
      regex: '(.*):\d+'
      target_label: instance
      replacement: '${1}'`
	return config + jobs
}

// calculateTimeout computes scrape_timeout = interval - 5s.
func calculateTimeout(interval string) string {
	interval = strings.TrimSpace(interval)
	if strings.HasSuffix(interval, "s") {
		secs, err := strconv.Atoi(strings.TrimSuffix(interval, "s"))
		if err == nil && secs > 5 {
			return fmt.Sprintf("%ds", secs-5)
		}
	}
	if strings.HasSuffix(interval, "m") {
		mins, err := strconv.Atoi(strings.TrimSuffix(interval, "m"))
		if err == nil {
			totalSecs := mins*60 - 5
			if totalSecs > 0 {
				return fmt.Sprintf("%ds", totalSecs)
			}
		}
	}
	return ""
}
