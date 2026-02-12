package stack

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"time"

	"github.com/scylladb/scylla-monitoring/scylla-monitor-ctl/pkg/docker"
	grafanaPkg "github.com/scylladb/scylla-monitoring/scylla-monitor-ctl/pkg/grafana"
)

// DeployOptions holds all options for deploying the monitoring stack.
type DeployOptions struct {
	ScyllaVersion       string
	ManagerVersion      string
	Enterprise          bool

	// Container images
	PrometheusImage     string
	GrafanaImage        string
	AlertManagerImage   string
	LokiImage           string
	PromtailImage       string
	RendererImage        string
	VictoriaMetricsImage string

	// Ports
	PrometheusPort      int
	GrafanaPort         int
	AlertManagerPort    int
	LokiPort            int
	PromtailPort        int
	PromtailBinaryPort  int

	// Storage
	DataDir             string // Prometheus data
	GrafanaDataDir      string
	LokiDataDir         string
	AlertManagerDataDir string

	// Target files
	TargetsFile         string
	NodeExporterFile    string
	ManagerTargetsFile  string
	VectorSearchFile    string
	TargetsDir          string

	// Prometheus
	ScrapeInterval      string
	EvaluationInterval  string
	NativeHistogram     bool
	DropMetrics         []string
	PrometheusOpts      []string
	AlertRules          string
	AdditionalTargets   []string

	// Grafana
	AdminPassword       string
	AnonymousRole       string
	BasicAuth           bool
	Anonymous           bool
	DisableAnonymous    bool
	LDAPConfigFile      string
	GrafanaEnv          []string
	ExtraDashboards     []string
	Solution            string
	SupportDashboard    bool
	ClearDashboards     bool

	// Components
	NoLoki              bool
	NoAlertManager      bool
	NoRenderer          bool
	VictoriaMetrics     bool

	// Docker
	AutoRestart         bool
	HostNetwork         bool
	BindAddress         string
	DockerParam         string
	ComposeMode         bool
	QuickStartup        bool

	// Multi-stack
	StackID             int

	// AlertManager
	AlertManagerConfig  string
	AlertManagerOpts    []string

	// Consul
	ConsulAddress       string

	// Runtime
	Runtime             docker.Runtime
}

// Deploy deploys the complete monitoring stack.
func Deploy(ctx context.Context, opts DeployOptions) error {
	rt := opts.Runtime
	networkName := docker.NetworkName(opts.StackID)

	// 1. Create Docker network (unless host networking)
	if !opts.HostNetwork {
		if err := docker.CreateNetwork(ctx, rt, opts.StackID); err != nil {
			return fmt.Errorf("creating network: %w", err)
		}
	}

	restartPolicy := ""
	if opts.AutoRestart {
		restartPolicy = "unless-stopped"
	}

	// 2. Start AlertManager
	if !opts.NoAlertManager {
		amName := docker.ContainerName("aalert", opts.AlertManagerPort, 9093)
		amConfig := opts.AlertManagerConfig
		if amConfig == "" {
			amConfig = "prometheus/rule_config.yml"
		}

		amCfg := docker.ContainerConfig{
			Name:          amName,
			Image:         opts.AlertManagerImage,
			NetworkName:   networkName,
			RestartPolicy: restartPolicy,
			HostNetwork:   opts.HostNetwork,
			BindAddress:   opts.BindAddress,
			PortBindings:  map[string]string{"9093/tcp": fmt.Sprintf("%d", opts.AlertManagerPort)},
			Mounts: []docker.MountConfig{
				{Source: absPath(amConfig), Target: "/etc/alertmanager/config.yml", ReadOnly: true},
			},
			Cmd: append([]string{"--config.file=/etc/alertmanager/config.yml"}, opts.AlertManagerOpts...),
		}
		if opts.AlertManagerDataDir != "" {
			amCfg.Mounts = append(amCfg.Mounts, docker.MountConfig{
				Source: absPath(opts.AlertManagerDataDir),
				Target: "/alertmanager",
			})
		}

		if _, err := docker.StartContainer(ctx, rt, amCfg); err != nil {
			return fmt.Errorf("starting AlertManager: %w", err)
		}

		if !opts.QuickStartup {
			url := fmt.Sprintf("http://localhost:%d/", opts.AlertManagerPort)
			if err := docker.WaitForHealth(ctx, url, 25, time.Second); err != nil {
				return fmt.Errorf("AlertManager health check: %w", err)
			}
		}
	}

	// 3. Start Loki + Promtail
	if !opts.NoLoki {
		lokiName := docker.ContainerName("loki", opts.LokiPort, 3100)

		lokiCfg := docker.ContainerConfig{
			Name:          lokiName,
			Image:         opts.LokiImage,
			NetworkName:   networkName,
			RestartPolicy: restartPolicy,
			HostNetwork:   opts.HostNetwork,
			BindAddress:   opts.BindAddress,
			PortBindings:  map[string]string{"3100/tcp": fmt.Sprintf("%d", opts.LokiPort)},
			Cmd:           []string{"-config.file=/etc/loki/local-config.yaml", "--ingester.wal-enabled=false"},
		}
		if opts.LokiDataDir != "" {
			lokiCfg.Mounts = append(lokiCfg.Mounts, docker.MountConfig{
				Source: absPath(opts.LokiDataDir),
				Target: "/loki",
			})
		}

		if _, err := docker.StartContainer(ctx, rt, lokiCfg); err != nil {
			return fmt.Errorf("starting Loki: %w", err)
		}

		if !opts.QuickStartup {
			url := fmt.Sprintf("http://localhost:%d/", opts.LokiPort)
			if err := docker.WaitForHealth(ctx, url, 25, time.Second); err != nil {
				return fmt.Errorf("Loki health check: %w", err)
			}
		}
		// Promtail
		promtailName := docker.ContainerName("promtail", opts.PromtailPort, 9080)
		promtailCfg := docker.ContainerConfig{
			Name:          promtailName,
			Image:         opts.PromtailImage,
			NetworkName:   networkName,
			RestartPolicy: restartPolicy,
			HostNetwork:   opts.HostNetwork,
			BindAddress:   opts.BindAddress,
			PortBindings: map[string]string{
				"9080/tcp": fmt.Sprintf("%d", opts.PromtailPort),
				"1514/tcp": fmt.Sprintf("%d", opts.PromtailBinaryPort),
			},
			Cmd: []string{"-config.file=/etc/promtail/config.yml"},
		}
		if _, err := docker.StartContainer(ctx, rt, promtailCfg); err != nil {
			return fmt.Errorf("starting Promtail: %w", err)
		}
	}

	// 4. Start Prometheus
	promName := docker.ContainerName("aprom", opts.PrometheusPort, 9090)
	promCmd := []string{
		"--config.file=/etc/prometheus/prometheus.yml",
		"--storage.tsdb.path=/prometheus",
		fmt.Sprintf("--web.listen-address=0.0.0.0:%d", 9090),
		"--web.enable-lifecycle",
	}
	promCmd = append(promCmd, opts.PrometheusOpts...)

	promMounts := []docker.MountConfig{
		{Source: absPath("prometheus/build/prometheus.yml"), Target: "/etc/prometheus/prometheus.yml", ReadOnly: true},
	}

	// Mount targets
	if opts.TargetsDir != "" {
		promMounts = append(promMounts, docker.MountConfig{
			Source: absPath(opts.TargetsDir), Target: "/etc/prometheus/targets", ReadOnly: true,
		})
	} else if opts.TargetsFile != "" {
		promMounts = append(promMounts, docker.MountConfig{
			Source: absPath(opts.TargetsFile), Target: "/etc/prometheus/targets/scylla_servers.yml", ReadOnly: true,
		})
	}

	// Mount alert rules
	ruleDir := opts.AlertRules
	if ruleDir == "" {
		ruleDir = "prometheus/prom_rules"
	}
	promMounts = append(promMounts, docker.MountConfig{
		Source: absPath(ruleDir), Target: "/etc/prometheus/prom_rules", ReadOnly: true,
	})

	// Data dir
	if opts.DataDir != "" {
		promMounts = append(promMounts, docker.MountConfig{
			Source: absPath(opts.DataDir), Target: "/prometheus",
		})
	}

	promImage := opts.PrometheusImage
	if opts.VictoriaMetrics {
		promImage = opts.VictoriaMetricsImage
		promCmd = []string{
			"--storageDataPath=/victoria-metrics-data",
			fmt.Sprintf("--httpListenAddr=:%d", 9090),
			"--promscrape.config=/etc/prometheus/prometheus.yml",
		}
	}

	promCfg := docker.ContainerConfig{
		Name:          promName,
		Image:         promImage,
		Cmd:           promCmd,
		NetworkName:   networkName,
		RestartPolicy: restartPolicy,
		HostNetwork:   opts.HostNetwork,
		BindAddress:   opts.BindAddress,
		PortBindings:  map[string]string{"9090/tcp": fmt.Sprintf("%d", opts.PrometheusPort)},
		Mounts:        promMounts,
	}

	if _, err := docker.StartContainer(ctx, rt, promCfg); err != nil {
		return fmt.Errorf("starting Prometheus: %w", err)
	}

	if !opts.QuickStartup {
		url := fmt.Sprintf("http://localhost:%d/", opts.PrometheusPort)
		if err := docker.WaitForHealth(ctx, url, 35, time.Second); err != nil {
			return fmt.Errorf("Prometheus health check: %w", err)
		}
	}

	// 5. Save metadata
	if opts.DataDir != "" {
		meta := fmt.Sprintf("version: %s\nmanager: %s\ndate: %s\n",
			opts.ScyllaVersion, opts.ManagerVersion, time.Now().Format(time.RFC3339))
		_ = os.MkdirAll(opts.DataDir, 0755)
		_ = os.WriteFile(filepath.Join(opts.DataDir, "scylla.txt"), []byte(meta), 0644)
	}

	// 6. Start Grafana
	grafName := docker.ContainerName("agraf", opts.GrafanaPort, 3000)

	grafOpts := grafanaPkg.GrafanaOptions{
		AdminPassword:    opts.AdminPassword,
		AnonymousRole:    opts.AnonymousRole,
		BasicAuth:        opts.BasicAuth,
		Anonymous:        opts.Anonymous,
		LDAPConfigFile:   opts.LDAPConfigFile,
		DisableAnonymous: opts.DisableAnonymous,
	}
	grafConfig, err := grafanaPkg.NewConfig(grafOpts)
	if err != nil {
		return fmt.Errorf("building Grafana config: %w", err)
	}

	// Convert env map to slice
	var grafEnv []string
	for k, v := range grafConfig.EnvVars {
		grafEnv = append(grafEnv, fmt.Sprintf("%s=%s", k, v))
	}
	grafEnv = append(grafEnv, "GF_PATHS_PROVISIONING=/var/lib/grafana/provisioning")
	grafEnv = append(grafEnv, "GF_PLUGINS_ALLOW_LOADING_UNSIGNED_PLUGINS=scylladb-scylla-datasource")
	grafEnv = append(grafEnv, "GF_DATABASE_WAL=true")
	grafEnv = append(grafEnv, opts.GrafanaEnv...)

	grafMounts := []docker.MountConfig{
		{Source: absPath("grafana/build"), Target: "/var/lib/grafana/dashboards"},
		{Source: absPath("grafana/plugins"), Target: "/var/lib/grafana/plugins"},
		{Source: absPath("grafana/provisioning"), Target: "/var/lib/grafana/provisioning"},
	}
	for _, vm := range grafConfig.VolumeMounts {
		grafMounts = append(grafMounts, docker.MountConfig{
			Source: vm.Source, Target: vm.Target, ReadOnly: vm.ReadOnly,
		})
	}
	if opts.GrafanaDataDir != "" {
		grafMounts = append(grafMounts, docker.MountConfig{
			Source: absPath(opts.GrafanaDataDir), Target: "/var/lib/grafana",
		})
	}

	grafCfg := docker.ContainerConfig{
		Name:          grafName,
		Image:         opts.GrafanaImage,
		Env:           grafEnv,
		NetworkName:   networkName,
		RestartPolicy: restartPolicy,
		HostNetwork:   opts.HostNetwork,
		BindAddress:   opts.BindAddress,
		PortBindings:  map[string]string{"3000/tcp": fmt.Sprintf("%d", opts.GrafanaPort)},
		Mounts:        grafMounts,
	}

	if _, err := docker.StartContainer(ctx, rt, grafCfg); err != nil {
		return fmt.Errorf("starting Grafana: %w", err)
	}

	if !opts.QuickStartup {
		url := fmt.Sprintf("http://localhost:%d/api/org", opts.GrafanaPort)
		if err := docker.WaitForHealth(ctx, url, 35, time.Second); err != nil {
			return fmt.Errorf("Grafana health check: %w", err)
		}
	}

	return nil
}

func absPath(path string) string {
	abs, err := filepath.Abs(path)
	if err != nil {
		return path
	}
	return abs
}
