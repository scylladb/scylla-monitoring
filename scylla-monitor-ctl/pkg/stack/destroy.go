package stack

import (
	"context"
	"log/slog"
	"time"

	"github.com/scylladb/scylla-monitoring/scylla-monitor-ctl/pkg/docker"
)

// DestroyOptions holds options for tearing down the monitoring stack.
type DestroyOptions struct {
	StackID          int
	PrometheusPort   int
	GrafanaPort      int
	AlertManagerPort int
	LokiPort         int
	PromtailPort     int
	Force            bool
	KeepData         bool
	GracePeriod      time.Duration // Prometheus graceful shutdown (default 120s)
	Runtime          docker.Runtime
}

// Destroy tears down the monitoring stack.
func Destroy(ctx context.Context, opts DestroyOptions) error {
	rt := opts.Runtime

	gracePeriod := opts.GracePeriod
	if gracePeriod == 0 {
		gracePeriod = 120 * time.Second
	}

	// Prometheus gets a longer graceful shutdown
	promName := docker.ContainerName("aprom", opts.PrometheusPort, 9090)
	if err := docker.StopContainer(ctx, rt, promName, gracePeriod); err != nil {
		slog.Warn("stopping container", "name", promName, "error", err)
	}

	// All other containers get a shorter timeout
	shortTimeout := 10 * time.Second
	containers := []string{
		docker.ContainerName("agraf", opts.GrafanaPort, 3000),
		docker.ContainerName("aalert", opts.AlertManagerPort, 9093),
		docker.ContainerName("loki", opts.LokiPort, 3100),
		docker.ContainerName("promtail", opts.PromtailPort, 9080),
	}

	// Extra containers only killed for primary stack
	if opts.StackID <= 0 {
		containers = append(containers,
			"agrafrender",
			"vmalert",
			"sidecar1",
		)
	}

	for _, name := range containers {
		if err := docker.StopContainer(ctx, rt, name, shortTimeout); err != nil {
			slog.Warn("stopping container", "name", name, "error", err)
		}
	}

	// Remove network
	if err := docker.RemoveNetwork(ctx, rt, opts.StackID); err != nil {
		slog.Warn("removing network", "error", err)
	}

	return nil
}
