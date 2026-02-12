package cmd

import (
	"fmt"

	"github.com/spf13/cobra"

	promPkg "github.com/scylladb/scylla-monitoring/scylla-monitor-ctl/pkg/prometheus"
)

var tuneFlags struct {
	ConfigPath         string
	PrometheusURL      string
	DropMetrics        []string
	DropMetricsRegex   []string
	KeepMetrics        []string
	ScrapeInterval     string
	EvaluationInterval string
	NativeHistogram    bool
	NoNativeHistogram  bool
	Reload             bool
}

var tuneCmd = &cobra.Command{
	Use:   "tune",
	Short: "Adjust Prometheus configuration on the fly",
	Long:  `Modify Prometheus metric filtering, scrape intervals, and other settings without restarting.`,
	RunE:  runTune,
}

func init() {
	rootCmd.AddCommand(tuneCmd)
	f := tuneCmd.Flags()
	f.StringVar(&tuneFlags.ConfigPath, "config-path", "prometheus/build/prometheus.yml", "Path to prometheus.yml")
	f.StringVar(&tuneFlags.PrometheusURL, "prometheus-url", "http://localhost:9090", "Prometheus URL")
	f.StringSliceVar(&tuneFlags.DropMetrics, "drop-metrics", nil, "Metric categories to drop (cas,cdc,alternator,...)")
	f.StringSliceVar(&tuneFlags.DropMetricsRegex, "drop-metrics-regex", nil, "Raw regex patterns to drop")
	f.StringSliceVar(&tuneFlags.KeepMetrics, "keep-metrics", nil, "Metric names to never drop")
	f.StringVar(&tuneFlags.ScrapeInterval, "scrape-interval", "", "Override scrape interval")
	f.StringVar(&tuneFlags.EvaluationInterval, "evaluation-interval", "", "Override evaluation interval")
	f.BoolVar(&tuneFlags.NativeHistogram, "native-histogram", false, "Enable native histogram scraping")
	f.BoolVar(&tuneFlags.NoNativeHistogram, "no-native-histogram", false, "Disable native histogram scraping")
	f.BoolVar(&tuneFlags.Reload, "reload", false, "Reload Prometheus after changes")
}

func runTune(cmd *cobra.Command, args []string) error {
	opts := promPkg.TuneOptions{
		ConfigPath:         tuneFlags.ConfigPath,
		DropMetrics:        tuneFlags.DropMetrics,
		DropMetricsRegex:   tuneFlags.DropMetricsRegex,
		KeepMetrics:        tuneFlags.KeepMetrics,
		ScrapeInterval:     tuneFlags.ScrapeInterval,
		EvaluationInterval: tuneFlags.EvaluationInterval,
		PrometheusURL:      tuneFlags.PrometheusURL,
		Reload:             tuneFlags.Reload,
	}

	if tuneFlags.NativeHistogram {
		enable := true
		opts.NativeHistogram = &enable
	} else if tuneFlags.NoNativeHistogram {
		disable := false
		opts.NativeHistogram = &disable
	}

	if err := promPkg.TuneConfig(opts); err != nil {
		return fmt.Errorf("tune failed: %w", err)
	}

	fmt.Println("Configuration updated.")
	if opts.Reload {
		fmt.Println("Prometheus reloaded.")
	}
	return nil
}
