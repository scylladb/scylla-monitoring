package cmd

import (
	"fmt"
	"os"
	"strings"

	"github.com/scylladb/scylla-monitoring/scylla-monitor-ctl/pkg/versions"
	"github.com/spf13/cobra"
)

// MonitorVersion is set at build time.
var MonitorVersion = "dev"

//go:generate cp ../assets/versions.yaml .
var versionsYAML []byte

func init() {
	// Try to load embedded versions data
	data, err := os.ReadFile("assets/versions.yaml")
	if err == nil {
		versionsYAML = data
	}
}

var versionFlags struct {
	Supported bool
}

var versionCmd = &cobra.Command{
	Use:   "version",
	Short: "Show version info and supported ScyllaDB versions",
	RunE: func(cmd *cobra.Command, args []string) error {
		fmt.Printf("scylla-monitor-ctl version %s\n", MonitorVersion)

		if !versionFlags.Supported {
			return nil
		}

		if len(versionsYAML) == 0 {
			// Try loading from file system
			data, err := os.ReadFile("assets/versions.yaml")
			if err != nil {
				return fmt.Errorf("versions data not available: %w", err)
			}
			versionsYAML = data
		}

		matrix, err := versions.Parse(versionsYAML)
		if err != nil {
			return fmt.Errorf("parsing version matrix: %w", err)
		}

		fmt.Println("\nContainer images:")
		fmt.Printf("  Prometheus:       %s\n", matrix.ContainerImages.Prometheus)
		fmt.Printf("  Grafana:          %s\n", matrix.ContainerImages.Grafana)
		fmt.Printf("  AlertManager:     %s\n", matrix.ContainerImages.AlertManager)
		fmt.Printf("  Loki:             %s\n", matrix.ContainerImages.Loki)
		fmt.Printf("  Grafana Renderer: %s\n", matrix.ContainerImages.GrafanaRenderer)
		fmt.Printf("  VictoriaMetrics:  %s\n", matrix.ContainerImages.VictoriaMetrics)

		fmt.Println("\nSupported stack versions:")
		for ver, sv := range matrix.StackVersions {
			fmt.Printf("  %s: ScyllaDB [%s] (default: %s), Manager [%s] (default: %s)\n",
				ver,
				strings.Join(sv.SupportedScylla, ", "),
				sv.DefaultScylla,
				strings.Join(sv.ManagerSupported, ", "),
				sv.ManagerDefault,
			)
		}

		return nil
	},
}

func init() {
	versionCmd.Flags().BoolVar(&versionFlags.Supported, "supported", false, "show supported ScyllaDB versions")
	rootCmd.AddCommand(versionCmd)
}
