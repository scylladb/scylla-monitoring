package cmd

import (
	"fmt"
	"log/slog"
	"os"
	"path/filepath"

	"github.com/spf13/cobra"

	"github.com/scylladb/scylla-monitoring/scylla-monitor-ctl/pkg/dashboard"
	"github.com/scylladb/scylla-monitoring/scylla-monitor-ctl/pkg/grafana"
	promPkg "github.com/scylladb/scylla-monitoring/scylla-monitor-ctl/pkg/prometheus"
)

var upgradeFlags struct {
	GrafanaConnFlags
	VersionFlags
	PrometheusURL    string
	ReloadPrometheus bool
}

var upgradeCmd = &cobra.Command{
	Use:   "upgrade",
	Short: "Upgrade dashboards and config on a running stack",
	Long:  `Update dashboards and configuration on a running monitoring stack without restart.`,
	RunE:  runUpgrade,
}

func init() {
	rootCmd.AddCommand(upgradeCmd)
	upgradeFlags.GrafanaConnFlags.Register(upgradeCmd, "http://localhost:3000")
	upgradeFlags.VersionFlags.Register(upgradeCmd)
	f := upgradeCmd.Flags()
	f.StringVar(&upgradeFlags.PrometheusURL, "prometheus-url", "", "Prometheus URL (for config reload)")
	f.BoolVar(&upgradeFlags.ReloadPrometheus, "reload-prometheus", false, "Reload Prometheus config after upgrade")
	upgradeCmd.MarkFlagRequired("scylla-version")
}

func runUpgrade(cmd *cobra.Command, args []string) error {
	gc := grafana.NewClient(upgradeFlags.URL, upgradeFlags.User, upgradeFlags.Password)

	// Generate dashboards
	typesData, err := os.ReadFile("grafana/types.json")
	if err != nil {
		return fmt.Errorf("reading types.json: %w", err)
	}

	gen, err := dashboard.NewGenerator(typesData)
	if err != nil {
		return fmt.Errorf("creating generator: %w", err)
	}
	gen.SetVersion(upgradeFlags.ScyllaVersion)

	dashboards := []string{"scylla-overview", "scylla-detailed", "scylla-os", "scylla-cql", "scylla-advanced", "alternator", "scylla-ks"}
	uploaded := 0
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
			continue
		}
		uploaded++
	}

	fmt.Printf("Uploaded %d dashboards.\n", uploaded)

	// Reload Prometheus if requested
	if upgradeFlags.ReloadPrometheus {
		promURL := upgradeFlags.PrometheusURL
		if promURL == "" {
			promURL = "http://localhost:9090"
		}
		pc := promPkg.NewClient(promURL)
		if err := pc.Reload(); err != nil {
			return fmt.Errorf("reloading Prometheus: %w", err)
		}
		fmt.Println("Prometheus configuration reloaded.")
	}

	return nil
}
