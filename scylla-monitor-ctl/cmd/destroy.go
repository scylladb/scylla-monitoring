package cmd

import (
	"context"
	"fmt"
	"time"

	"github.com/spf13/cobra"

	"github.com/scylladb/scylla-monitoring/scylla-monitor-ctl/pkg/docker"
	"github.com/scylladb/scylla-monitoring/scylla-monitor-ctl/pkg/stack"
)

var destroyFlags struct {
	StackPortFlags
	Force    bool
	KeepData bool
	Wait     int
}

var destroyCmd = &cobra.Command{
	Use:   "destroy",
	Short: "Tear down the monitoring stack",
	Long:  `Stop and remove all monitoring stack containers and the Docker network.`,
	RunE:  runDestroy,
}

func init() {
	rootCmd.AddCommand(destroyCmd)
	destroyFlags.StackPortFlags.Register(destroyCmd)
	f := destroyCmd.Flags()
	f.BoolVar(&destroyFlags.Force, "force", false, "Force kill containers")
	f.BoolVar(&destroyFlags.KeepData, "keep-data", false, "Keep data directories")
	f.IntVar(&destroyFlags.Wait, "wait", 120, "Max wait time for Prometheus shutdown (seconds)")
}

func runDestroy(cmd *cobra.Command, args []string) error {
	runtime, _ := docker.DetectRuntime(cmd.Context())

	opts := stack.DestroyOptions{
		StackID:          destroyFlags.StackID,
		PrometheusPort:   destroyFlags.PrometheusPort,
		GrafanaPort:      destroyFlags.GrafanaPort,
		AlertManagerPort: destroyFlags.AlertManagerPort,
		LokiPort:         destroyFlags.LokiPort,
		PromtailPort:     destroyFlags.PromtailPort,
		Force:            destroyFlags.Force,
		KeepData:         destroyFlags.KeepData,
		GracePeriod:      time.Duration(destroyFlags.Wait) * time.Second,
		Runtime:          runtime,
	}

	ctx := context.Background()
	if err := stack.Destroy(ctx, opts); err != nil {
		return fmt.Errorf("destroy failed: %w", err)
	}

	fmt.Println("Monitoring stack destroyed.")
	return nil
}
