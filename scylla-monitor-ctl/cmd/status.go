package cmd

import (
	"context"
	"fmt"

	"github.com/spf13/cobra"

	"github.com/scylladb/scylla-monitoring/scylla-monitor-ctl/pkg/docker"
	"github.com/scylladb/scylla-monitoring/scylla-monitor-ctl/pkg/stack"
)

var statusFlags struct {
	StackPortFlags
}

var statusCmd = &cobra.Command{
	Use:   "status",
	Short: "Show status of the monitoring stack",
	Long:  `Display the health and status of all monitoring stack components.`,
	RunE:  runStatus,
}

func init() {
	rootCmd.AddCommand(statusCmd)
	statusFlags.StackPortFlags.Register(statusCmd)
}

func runStatus(cmd *cobra.Command, args []string) error {
	runtime, _ := docker.DetectRuntime(cmd.Context())

	opts := stack.StatusOptions{
		StackID:          statusFlags.StackID,
		PrometheusPort:   statusFlags.PrometheusPort,
		GrafanaPort:      statusFlags.GrafanaPort,
		AlertManagerPort: statusFlags.AlertManagerPort,
		LokiPort:         statusFlags.LokiPort,
		PromtailPort:     statusFlags.PromtailPort,
		Runtime:          runtime,
	}

	ctx := context.Background()
	ss, err := stack.GetStatus(ctx, opts)
	if err != nil {
		return fmt.Errorf("getting status: %w", err)
	}

	fmt.Print(ss.FormatTable())
	return nil
}
