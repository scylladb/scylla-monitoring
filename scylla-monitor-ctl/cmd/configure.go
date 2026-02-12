package cmd

import (
	"fmt"
	"log/slog"
	"os"
	"path/filepath"

	"github.com/spf13/cobra"

	"github.com/scylladb/scylla-monitoring/scylla-monitor-ctl/pkg/dashboard"
	"github.com/scylladb/scylla-monitoring/scylla-monitor-ctl/pkg/grafana"
)

var configureFlags struct {
	GrafanaConnFlags
	VersionFlags
	PrometheusURL   string
	AlertManagerURL string
	LokiURL         string
}

var configureCmd = &cobra.Command{
	Use:   "configure",
	Short: "Configure a pre-existing Grafana+Prometheus for ScyllaDB",
	Long:  `Create/update datasources and upload dashboards to an existing Grafana instance.`,
	RunE:  runConfigure,
}

func init() {
	rootCmd.AddCommand(configureCmd)
	configureFlags.GrafanaConnFlags.Register(configureCmd, "http://localhost:3000")
	configureFlags.VersionFlags.Register(configureCmd)
	f := configureCmd.Flags()
	f.StringVar(&configureFlags.PrometheusURL, "prometheus-url", "http://localhost:9090", "Prometheus URL")
	f.StringVar(&configureFlags.AlertManagerURL, "alertmanager-url", "", "AlertManager URL")
	f.StringVar(&configureFlags.LokiURL, "loki-url", "", "Loki URL")
}

func runConfigure(cmd *cobra.Command, args []string) error {
	gc := grafana.NewClient(configureFlags.URL, configureFlags.User, configureFlags.Password)

	// Create datasources
	if configureFlags.PrometheusURL != "" {
		if err := gc.CreateDatasource(grafana.APIDatasource{
			Name:      "prometheus",
			Type:      "prometheus",
			URL:       configureFlags.PrometheusURL,
			Access:    "proxy",
			IsDefault: true,
		}); err != nil {
			slog.Warn("creating datasource", "datasource", "prometheus", "error", err)
		}
	}

	if configureFlags.AlertManagerURL != "" {
		if err := gc.CreateDatasource(grafana.APIDatasource{
			Name:   "alertmanager",
			Type:   "alertmanager",
			URL:    configureFlags.AlertManagerURL,
			Access: "proxy",
			JSONData: map[string]interface{}{
				"implementation": "prometheus",
			},
		}); err != nil {
			slog.Warn("creating datasource", "datasource", "alertmanager", "error", err)
		}
	}

	if configureFlags.LokiURL != "" {
		if err := gc.CreateDatasource(grafana.APIDatasource{
			Name:   "loki",
			Type:   "loki",
			URL:    configureFlags.LokiURL,
			Access: "proxy",
		}); err != nil {
			slog.Warn("creating datasource", "datasource", "loki", "error", err)
		}
	}

	// Generate and upload dashboards
	if configureFlags.ScyllaVersion != "" {
		typesData, err := os.ReadFile("grafana/types.json")
		if err != nil {
			return fmt.Errorf("reading types.json: %w", err)
		}

		gen, err := dashboard.NewGenerator(typesData)
		if err != nil {
			return fmt.Errorf("creating generator: %w", err)
		}
		gen.SetVersion(configureFlags.ScyllaVersion)

		dashboards := []string{"scylla-overview", "scylla-detailed", "scylla-os", "scylla-cql", "scylla-advanced", "alternator", "scylla-ks"}
		for _, name := range dashboards {
			templatePath := filepath.Join("grafana", name+".template.json")
			templateData, err := os.ReadFile(templatePath)
			if err != nil {
				slog.Warn("reading template", "dashboard", name, "error", err)
				continue
			}
			dashJSON, err := gen.Generate(templateData)
			if err != nil {
				slog.Warn("generating dashboard", "dashboard", name, "error", err)
				continue
			}
			if err := gc.UploadDashboard(dashJSON, 0, true); err != nil {
				slog.Warn("uploading dashboard", "dashboard", name, "error", err)
			}
		}
	}

	fmt.Println("Configuration complete.")
	return nil
}
