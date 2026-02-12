package cmd

import (
	"fmt"
	"log/slog"

	"github.com/spf13/cobra"

	"github.com/scylladb/scylla-monitoring/scylla-monitor-ctl/pkg/migrate"
)

var backupCreateFlags struct {
	GrafanaConnFlags
	PrometheusURL      string
	Output             string
	PrometheusConfig   string
	AlertRulesDir      string
	AlertManagerConfig string
	TargetFiles        []string
}

var backupRestoreFlags struct {
	GrafanaConnFlags
	Archive string
}

var backupCmd = &cobra.Command{
	Use:   "backup",
	Short: "Backup and restore operations",
	Long: `Create and restore lightweight backups of monitoring stack configs and dashboards.

This is a convenience wrapper around 'migrate export' and 'migrate import' with
sensible defaults for local backup/restore workflows. For full migration options
(e.g. Loki config, data directories), use the 'migrate' command directly.`,
}

var backupCreateCmd = &cobra.Command{
	Use:   "create",
	Short: "Create a backup of the monitoring stack",
	Long: `Create a lightweight backup of configs and dashboards.

Prometheus metric data is included automatically when --prometheus-url is provided.
Without it, only configuration files and Grafana dashboards/datasources are backed up.`,
	RunE:  runBackupCreate,
}

var backupRestoreCmd = &cobra.Command{
	Use:   "restore",
	Short: "Restore from a backup archive",
	RunE:  runBackupRestore,
}

func init() {
	rootCmd.AddCommand(backupCmd)
	backupCmd.AddCommand(backupCreateCmd)
	backupCmd.AddCommand(backupRestoreCmd)

	// Create flags
	backupCreateFlags.GrafanaConnFlags.Register(backupCreateCmd, "")
	cf := backupCreateCmd.Flags()
	cf.StringVar(&backupCreateFlags.PrometheusURL, "prometheus-url", "", "Prometheus URL (enables metric data backup)")
	cf.StringVar(&backupCreateFlags.Output, "output", "monitoring-backup.tar.gz", "Output archive path")
	cf.StringVar(&backupCreateFlags.PrometheusConfig, "prometheus-config", "prometheus/build/prometheus.yml", "Prometheus config path")
	cf.StringVar(&backupCreateFlags.AlertRulesDir, "alert-rules-dir", "prometheus/prom_rules", "Alert rules directory")
	cf.StringVar(&backupCreateFlags.AlertManagerConfig, "alertmanager-config", "prometheus/rule_config.yml", "AlertManager config")
	cf.StringSliceVar(&backupCreateFlags.TargetFiles, "target-files", nil, "Target files to include")

	// Restore flags
	backupRestoreFlags.GrafanaConnFlags.Register(backupRestoreCmd, "")
	rf := backupRestoreCmd.Flags()
	rf.StringVar(&backupRestoreFlags.Archive, "archive", "", "Backup archive path (required)")
	backupRestoreCmd.MarkFlagRequired("archive")
}

func runBackupCreate(cmd *cobra.Command, args []string) error {
	if backupCreateFlags.PrometheusURL == "" {
		slog.Warn("no --prometheus-url provided, metric data will not be included in the backup")
	}

	opts := migrate.ArchiveOptions{
		GrafanaURL:         backupCreateFlags.URL,
		GrafanaUser:        backupCreateFlags.User,
		GrafanaPassword:    backupCreateFlags.Password,
		PrometheusURL:      backupCreateFlags.PrometheusURL,
		OutputPath:         backupCreateFlags.Output,
		PrometheusConfig:   backupCreateFlags.PrometheusConfig,
		AlertRulesDir:      backupCreateFlags.AlertRulesDir,
		AlertManagerConfig: backupCreateFlags.AlertManagerConfig,
		TargetFiles:        backupCreateFlags.TargetFiles,
	}

	if err := migrate.ArchiveStack(opts); err != nil {
		return fmt.Errorf("backup create failed: %w", err)
	}
	fmt.Printf("Backup created: %s\n", opts.OutputPath)
	return nil
}

func runBackupRestore(cmd *cobra.Command, args []string) error {
	opts := migrate.RestoreOptions{
		ArchivePath:     backupRestoreFlags.Archive,
		GrafanaURL:      backupRestoreFlags.URL,
		GrafanaUser:     backupRestoreFlags.User,
		GrafanaPassword: backupRestoreFlags.Password,
	}

	if err := migrate.RestoreStack(opts); err != nil {
		return fmt.Errorf("backup restore failed: %w", err)
	}
	fmt.Println("Backup restored successfully.")
	return nil
}
