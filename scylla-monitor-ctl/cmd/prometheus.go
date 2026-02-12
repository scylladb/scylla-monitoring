package cmd

import (
	"fmt"
	"os"

	"github.com/scylladb/scylla-monitoring/scylla-monitor-ctl/pkg/prometheus"
	"github.com/spf13/cobra"
)

var promConfigFlags struct {
	AlertManagerAddress string
	GrafanaAddress      string
	Output              string
	ConsulAddress       string
	DropMetrics         []string
	ScrapeInterval      string
	EvaluationInterval  string
	NativeHistogram     bool
	VectorSearch        bool
	ExtraTargets        []string
	Template            string
}

var promReloadFlags struct {
	PrometheusURL string
}

var prometheusCmd = &cobra.Command{
	Use:   "prometheus",
	Short: "Prometheus configuration management",
}

var prometheusReloadCmd = &cobra.Command{
	Use:   "reload",
	Short: "Trigger a hot-reload of Prometheus configuration",
	RunE: func(cmd *cobra.Command, args []string) error {
		pc := prometheus.NewClient(promReloadFlags.PrometheusURL)
		if err := pc.Reload(); err != nil {
			return fmt.Errorf("reload failed: %w", err)
		}
		fmt.Println("Prometheus configuration reloaded.")
		return nil
	},
}

var prometheusConfigCmd = &cobra.Command{
	Use:   "config",
	Short: "Generate prometheus.yml",
	RunE:  runPrometheusConfig,
}

func runPrometheusConfig(cmd *cobra.Command, args []string) error {
	output := promConfigFlags.Output
	if output == "" {
		output = "prometheus/build/prometheus.yml"
	}

	// Load template
	var templateData []byte
	var err error
	if promConfigFlags.Template != "" {
		templateData, err = os.ReadFile(promConfigFlags.Template)
		if err != nil {
			return fmt.Errorf("reading template: %w", err)
		}
	} else if promConfigFlags.ConsulAddress != "" {
		templateData, err = os.ReadFile("prometheus/prometheus.consul.yml.template")
		if err != nil {
			return fmt.Errorf("reading consul template: %w", err)
		}
	} else {
		templateData, err = os.ReadFile("prometheus/prometheus.yml.template")
		if err != nil {
			return fmt.Errorf("reading template: %w", err)
		}
	}

	opts := prometheus.ConfigOptions{
		AlertManagerAddress: promConfigFlags.AlertManagerAddress,
		GrafanaAddress:      promConfigFlags.GrafanaAddress,
		ManagerAddress:      promConfigFlags.ConsulAddress,
		UseConsul:           promConfigFlags.ConsulAddress != "",
		DropMetrics:         promConfigFlags.DropMetrics,
		ScrapeInterval:      promConfigFlags.ScrapeInterval,
		EvaluationInterval:  promConfigFlags.EvaluationInterval,
		NativeHistogram:     promConfigFlags.NativeHistogram,
		VectorSearch:        promConfigFlags.VectorSearch,
		AdditionalTargets:   promConfigFlags.ExtraTargets,
		OutputPath:          output,
	}

	if err := prometheus.WriteConfig(templateData, opts); err != nil {
		return fmt.Errorf("generating config: %w", err)
	}

	fmt.Printf("Wrote prometheus config to %s\n", output)
	return nil
}

func init() {
	pcf := prometheusConfigCmd.Flags()
	pcf.StringVar(&promConfigFlags.AlertManagerAddress, "alertmanager-address", "aalert:9093", "AlertManager address:port")
	pcf.StringVar(&promConfigFlags.GrafanaAddress, "grafana-address", "agraf:3000", "Grafana address:port")
	pcf.StringVar(&promConfigFlags.Output, "output", "", "output path (default: prometheus/build/prometheus.yml)")
	pcf.StringVar(&promConfigFlags.ConsulAddress, "consul-address", "", "Consul/Manager address for service discovery")
	pcf.StringSliceVar(&promConfigFlags.DropMetrics, "drop-metrics", nil, "metric categories or patterns to drop")
	pcf.StringVar(&promConfigFlags.ScrapeInterval, "scrape-interval", "", "override scrape interval")
	pcf.StringVar(&promConfigFlags.EvaluationInterval, "evaluation-interval", "", "override evaluation interval")
	pcf.BoolVar(&promConfigFlags.NativeHistogram, "native-histogram", false, "enable native histogram scraping")
	pcf.BoolVar(&promConfigFlags.VectorSearch, "vector-search", false, "add vector search scrape jobs")
	pcf.StringSliceVar(&promConfigFlags.ExtraTargets, "extra-targets", nil, "additional target files to append")
	pcf.StringVar(&promConfigFlags.Template, "template", "", "custom template file path")

	prometheusReloadCmd.Flags().StringVar(&promReloadFlags.PrometheusURL, "prometheus-url", "http://localhost:9090", "Prometheus URL")

	prometheusCmd.AddCommand(prometheusConfigCmd)
	prometheusCmd.AddCommand(prometheusReloadCmd)
	rootCmd.AddCommand(prometheusCmd)
}
