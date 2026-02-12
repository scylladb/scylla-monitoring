package cmd

import (
	"fmt"
	"log/slog"

	"github.com/spf13/cobra"

	"github.com/scylladb/scylla-monitoring/scylla-monitor-ctl/pkg/migrate"
)

var migrateExportFlags struct {
	GrafanaConnFlags
	PrometheusURL      string
	Output             string
	PrometheusConfig   string
	AlertRulesDir      string
	AlertManagerConfig string
	LokiConfig         string
	TargetFiles        []string
}

var migrateImportFlags struct {
	GrafanaConnFlags
	Archive        string
	DataDir        string
	GrafanaDataDir string
	GrafanaPort    int
}

var migrateCopyFlags struct {
	Source              GrafanaConnFlags
	Target              GrafanaConnFlags
	IncludeDashboards   bool
	IncludeDatasources  bool
}

var migrateCmd = &cobra.Command{
	Use:   "migrate",
	Short: "Stack migration operations",
	Long:  `Export, import, or copy monitoring stack configurations and data.`,
}

var migrateExportCmd = &cobra.Command{
	Use:   "export",
	Short: "Export a monitoring stack",
	Long: `Export dashboards, datasources, configs, and optionally data to an archive.

Prometheus metric data is included automatically when --prometheus-url is provided.
Without it, only configuration files and Grafana dashboards/datasources are exported.`,
	RunE:  runMigrateExport,
}

var migrateImportCmd = &cobra.Command{
	Use:   "import",
	Short: "Import a monitoring stack from an archive",
	Long:  `Restore dashboards, configs, and optionally data from an export archive.`,
	RunE:  runMigrateImport,
}

var migrateCopyCmd = &cobra.Command{
	Use:   "copy",
	Short: "Live copy from one stack to another",
	Long:  `Copy dashboards and datasources from a source Grafana to a target.`,
	RunE:  runMigrateCopy,
}

func init() {
	rootCmd.AddCommand(migrateCmd)
	migrateCmd.AddCommand(migrateExportCmd)
	migrateCmd.AddCommand(migrateImportCmd)
	migrateCmd.AddCommand(migrateCopyCmd)

	// Export flags
	migrateExportFlags.GrafanaConnFlags.Register(migrateExportCmd, "")
	ef := migrateExportCmd.Flags()
	ef.StringVar(&migrateExportFlags.PrometheusURL, "prometheus-url", "", "Prometheus URL (enables metric data export)")
	ef.StringVar(&migrateExportFlags.Output, "output", "stack-export.tar.gz", "Output archive path")
	ef.StringVar(&migrateExportFlags.PrometheusConfig, "prometheus-config", "", "Path to prometheus.yml")
	ef.StringVar(&migrateExportFlags.AlertRulesDir, "alert-rules-dir", "", "Path to alert rules directory")
	ef.StringVar(&migrateExportFlags.AlertManagerConfig, "alertmanager-config", "", "Path to AlertManager config")
	ef.StringVar(&migrateExportFlags.LokiConfig, "loki-config", "", "Path to Loki config")
	ef.StringSliceVar(&migrateExportFlags.TargetFiles, "target-files", nil, "Target files to include")

	// Import flags
	migrateImportFlags.GrafanaConnFlags.Register(migrateImportCmd, "")
	imf := migrateImportCmd.Flags()
	imf.StringVar(&migrateImportFlags.Archive, "archive", "", "Path to export archive (required)")
	imf.StringVar(&migrateImportFlags.DataDir, "data-dir", "", "Prometheus data directory")
	imf.StringVar(&migrateImportFlags.GrafanaDataDir, "grafana-data-dir", "", "Grafana data directory")
	imf.IntVar(&migrateImportFlags.GrafanaPort, "grafana-port", 3000, "Grafana port")
	migrateImportCmd.MarkFlagRequired("archive")

	// Copy flags
	migrateCopyFlags.Source.RegisterWithPrefix(migrateCopyCmd, "source-", "Source")
	migrateCopyFlags.Target.RegisterWithPrefix(migrateCopyCmd, "target-", "Target")
	cf := migrateCopyCmd.Flags()
	cf.BoolVar(&migrateCopyFlags.IncludeDashboards, "include-dashboards", true, "Copy dashboards")
	cf.BoolVar(&migrateCopyFlags.IncludeDatasources, "include-datasources", true, "Copy datasources")
	migrateCopyCmd.MarkFlagRequired("source-grafana-url")
	migrateCopyCmd.MarkFlagRequired("target-grafana-url")
}

func runMigrateExport(cmd *cobra.Command, args []string) error {
	if migrateExportFlags.PrometheusURL == "" {
		slog.Warn("no --prometheus-url provided, metric data will not be included in the export")
	}

	opts := migrate.ArchiveOptions{
		PrometheusURL:      migrateExportFlags.PrometheusURL,
		GrafanaURL:         migrateExportFlags.URL,
		GrafanaUser:        migrateExportFlags.User,
		GrafanaPassword:    migrateExportFlags.Password,
		OutputPath:         migrateExportFlags.Output,
		PrometheusConfig:   migrateExportFlags.PrometheusConfig,
		AlertRulesDir:      migrateExportFlags.AlertRulesDir,
		AlertManagerConfig: migrateExportFlags.AlertManagerConfig,
		LokiConfig:         migrateExportFlags.LokiConfig,
		TargetFiles:        migrateExportFlags.TargetFiles,
	}

	if err := migrate.ArchiveStack(opts); err != nil {
		return fmt.Errorf("export failed: %w", err)
	}
	fmt.Printf("Stack exported to %s\n", opts.OutputPath)
	return nil
}

func runMigrateImport(cmd *cobra.Command, args []string) error {
	opts := migrate.RestoreOptions{
		ArchivePath:     migrateImportFlags.Archive,
		DataDir:         migrateImportFlags.DataDir,
		GrafanaDataDir:  migrateImportFlags.GrafanaDataDir,
		GrafanaURL:      migrateImportFlags.URL,
		GrafanaUser:     migrateImportFlags.User,
		GrafanaPassword: migrateImportFlags.Password,
		GrafanaPort:     migrateImportFlags.GrafanaPort,
	}

	if err := migrate.RestoreStack(opts); err != nil {
		return fmt.Errorf("import failed: %w", err)
	}
	fmt.Println("Stack imported successfully.")
	return nil
}

func runMigrateCopy(cmd *cobra.Command, args []string) error {
	opts := migrate.CopyOptions{
		SourceGrafanaURL:      migrateCopyFlags.Source.URL,
		SourceGrafanaUser:     migrateCopyFlags.Source.User,
		SourceGrafanaPassword: migrateCopyFlags.Source.Password,
		TargetGrafanaURL:      migrateCopyFlags.Target.URL,
		TargetGrafanaUser:     migrateCopyFlags.Target.User,
		TargetGrafanaPassword: migrateCopyFlags.Target.Password,
		IncludeDashboards:     migrateCopyFlags.IncludeDashboards,
		IncludeDatasources:    migrateCopyFlags.IncludeDatasources,
	}

	if err := migrate.Copy(opts); err != nil {
		return fmt.Errorf("copy failed: %w", err)
	}
	fmt.Println("Stack copied successfully.")
	return nil
}
