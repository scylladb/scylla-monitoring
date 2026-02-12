package prometheus

import (
	"fmt"
	"os"
	"strings"
)

// TuneOptions holds options for modifying a running Prometheus configuration.
type TuneOptions struct {
	ConfigPath         string   // path to prometheus.yml
	DropMetrics        []string // category names or regex patterns to add
	KeepMetrics        []string // metric names that should never be dropped
	DropMetricsRegex   []string // raw regex patterns to add
	ScrapeInterval     string
	EvaluationInterval string
	NativeHistogram    *bool // nil = don't change, true/false = set
	PrometheusURL      string
	Reload             bool
}

// TuneConfig reads, modifies, and writes a prometheus.yml file.
func TuneConfig(opts TuneOptions) error {
	data, err := os.ReadFile(opts.ConfigPath)
	if err != nil {
		return fmt.Errorf("reading config: %w", err)
	}

	config := string(data)

	// Add metric drop rules
	allDropPatterns := ResolveDropPatterns(opts.DropMetrics)
	allDropPatterns = append(allDropPatterns, opts.DropMetricsRegex...)

	// Filter out keep-metrics from drop patterns
	if len(opts.KeepMetrics) > 0 {
		var filtered []string
		for _, pattern := range allDropPatterns {
			keep := false
			for _, km := range opts.KeepMetrics {
				if strings.Contains(pattern, km) {
					keep = true
					break
				}
			}
			if !keep {
				filtered = append(filtered, pattern)
			}
		}
		allDropPatterns = filtered
	}

	if len(allDropPatterns) > 0 {
		config = addDropRules(config, allDropPatterns)
	}

	// Scrape interval
	if opts.ScrapeInterval != "" {
		config = tuneScrapeInterval(config, opts.ScrapeInterval)
	}

	// Evaluation interval
	if opts.EvaluationInterval != "" {
		config = tuneEvaluationInterval(config, opts.EvaluationInterval)
	}

	// Native histogram
	if opts.NativeHistogram != nil {
		config = tuneNativeHistogram(config, *opts.NativeHistogram)
	}

	if err := os.WriteFile(opts.ConfigPath, []byte(config), 0644); err != nil {
		return fmt.Errorf("writing config: %w", err)
	}

	// Reload if requested
	if opts.Reload && opts.PrometheusURL != "" {
		client := NewClient(opts.PrometheusURL)
		if err := client.Reload(); err != nil {
			return fmt.Errorf("reloading prometheus: %w", err)
		}
	}

	return nil
}

func addDropRules(config string, patterns []string) string {
	// Find the scylla job's metric_relabel_configs section or FILTER_METRICS marker
	var filterLines []string
	for _, p := range patterns {
		filterLines = append(filterLines,
			"    - source_labels: [__name__]",
			"      regex: '"+p+"'",
			"      action: drop",
		)
	}
	filterBlock := strings.Join(filterLines, "\n")

	// Try the marker first
	if strings.Contains(config, "# FILTER_METRICS") {
		return strings.Replace(config, "# FILTER_METRICS", filterBlock, 1)
	}

	// Otherwise append to the scylla job's metric_relabel_configs
	if strings.Contains(config, "metric_relabel_configs:") {
		// Find the first metric_relabel_configs and append after it
		idx := strings.Index(config, "metric_relabel_configs:")
		insertPoint := idx + len("metric_relabel_configs:")
		// Find the next line
		nextNewline := strings.Index(config[insertPoint:], "\n")
		if nextNewline >= 0 {
			insertPoint += nextNewline + 1
		}
		config = config[:insertPoint] + filterBlock + "\n" + config[insertPoint:]
		return config
	}

	// Fallback: append before the end of the scylla job
	return config + "\n    metric_relabel_configs:\n" + filterBlock + "\n"
}

func tuneScrapeInterval(config, interval string) string {
	// Replace scrape_interval in the global section
	lines := strings.Split(config, "\n")
	for i, line := range lines {
		trimmed := strings.TrimSpace(line)
		if strings.HasPrefix(trimmed, "scrape_interval:") {
			indent := line[:len(line)-len(strings.TrimLeft(line, " \t"))]
			lines[i] = indent + "scrape_interval: " + interval
			// Also adjust timeout on the next line if it exists
			timeout := calculateTimeout(interval)
			if timeout != "" && i+1 < len(lines) {
				nextTrimmed := strings.TrimSpace(lines[i+1])
				if strings.HasPrefix(nextTrimmed, "scrape_timeout:") {
					nextIndent := lines[i+1][:len(lines[i+1])-len(strings.TrimLeft(lines[i+1], " \t"))]
					lines[i+1] = nextIndent + "scrape_timeout: " + timeout
				}
			}
			break
		}
	}
	return strings.Join(lines, "\n")
}

func tuneEvaluationInterval(config, interval string) string {
	lines := strings.Split(config, "\n")
	for i, line := range lines {
		trimmed := strings.TrimSpace(line)
		if strings.HasPrefix(trimmed, "evaluation_interval:") {
			indent := line[:len(line)-len(strings.TrimLeft(line, " \t"))]
			lines[i] = indent + "evaluation_interval: " + interval
			break
		}
	}
	return strings.Join(lines, "\n")
}

func tuneNativeHistogram(config string, enable bool) string {
	if enable {
		if strings.Contains(config, "scrape_native_histograms:") {
			// Already present, ensure it's true
			config = strings.Replace(config, "scrape_native_histograms: false", "scrape_native_histograms: true", 1)
		} else {
			// Add before scrape_interval
			config = strings.Replace(config, "scrape_interval:", "scrape_native_histograms: true\n  scrape_interval:", 1)
		}
	} else {
		if strings.Contains(config, "scrape_native_histograms: true") {
			config = strings.Replace(config, "scrape_native_histograms: true\n  ", "", 1)
		}
	}
	return config
}
