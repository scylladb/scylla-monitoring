package cmd

import (
	"context"
	"fmt"

	"github.com/spf13/cobra"

	"github.com/scylladb/scylla-monitoring/scylla-monitor-ctl/pkg/docker"
	"github.com/scylladb/scylla-monitoring/scylla-monitor-ctl/pkg/stack"
)

var deployFlags struct {
	VersionFlags
	StackPortFlags
	Enterprise         bool
	PromtailBinaryPort int

	// Storage
	DataDir             string
	GrafanaDataDir      string
	LokiDataDir         string
	AlertManagerDataDir string

	// Targets
	TargetsFile        string
	NodeExporterFile   string
	ManagerTargetsFile string
	VectorSearchFile   string
	TargetsDir         string

	// Prometheus
	ScrapeInterval     string
	EvaluationInterval string
	NativeHistogram    bool
	DropMetrics        []string
	PrometheusOpts     []string
	AlertRules         string
	AdditionalTargets  []string

	// Grafana
	AdminPassword    string
	AnonymousRole    string
	Auth             bool
	DisableAnonymous bool
	LDAPConfig       string
	GrafanaEnv       []string
	ExtraDashboards  []string
	Solution         string
	SupportDashboard bool
	ClearDashboards  bool

	// Components
	NoLoki          bool
	NoAlertManager  bool
	NoRenderer      bool
	VictoriaMetrics bool

	// Docker
	AutoRestart  bool
	HostNetwork  bool
	BindAddress  string
	DockerParam  string
	QuickStartup bool
	Mode         string

	// AlertManager
	AlertManagerConfig string
	AlertManagerOpts   []string

	// Consul
	ConsulAddress string
}

var deployCmd = &cobra.Command{
	Use:   "deploy",
	Short: "Deploy a monitoring stack",
	Long:  `Deploy a complete ScyllaDB monitoring stack (Prometheus, Grafana, AlertManager, Loki).`,
	RunE:  runDeploy,
}

func init() {
	rootCmd.AddCommand(deployCmd)
	deployFlags.VersionFlags.Register(deployCmd)
	deployFlags.StackPortFlags.Register(deployCmd)

	f := deployCmd.Flags()

	// Core
	f.BoolVar(&deployFlags.Enterprise, "enterprise", false, "Use enterprise default versions")

	// Extra ports
	f.IntVar(&deployFlags.PromtailBinaryPort, "promtail-binary-port", 1514, "Promtail binary protocol port")

	// Storage
	f.StringVar(&deployFlags.DataDir, "data-dir", "", "Prometheus data directory")
	f.StringVar(&deployFlags.GrafanaDataDir, "grafana-data-dir", "", "Grafana data directory")
	f.StringVar(&deployFlags.LokiDataDir, "loki-data-dir", "", "Loki data directory")
	f.StringVar(&deployFlags.AlertManagerDataDir, "alertmanager-data-dir", "", "AlertManager data directory")

	// Targets
	f.StringVar(&deployFlags.TargetsFile, "targets-file", "", "ScyllaDB targets file")
	f.StringVar(&deployFlags.NodeExporterFile, "node-exporter-file", "", "Node exporter targets file")
	f.StringVar(&deployFlags.ManagerTargetsFile, "manager-targets-file", "", "Scylla Manager targets file")
	f.StringVar(&deployFlags.VectorSearchFile, "vector-search-file", "", "Vector search targets file")
	f.StringVar(&deployFlags.TargetsDir, "targets-dir", "", "Directory containing target files")

	// Prometheus
	f.StringVar(&deployFlags.ScrapeInterval, "scrape-interval", "", "Prometheus scrape interval")
	f.StringVar(&deployFlags.EvaluationInterval, "evaluation-interval", "", "Prometheus evaluation interval")
	f.BoolVar(&deployFlags.NativeHistogram, "native-histogram", false, "Enable native histogram scraping")
	f.StringSliceVar(&deployFlags.DropMetrics, "drop-metrics", nil, "Metric categories to drop (cas,cdc,alternator,...)")
	f.StringSliceVar(&deployFlags.PrometheusOpts, "prometheus-opt", nil, "Additional Prometheus command line options")
	f.StringVar(&deployFlags.AlertRules, "alert-rules", "", "Custom alert rules file or directory")
	f.StringSliceVar(&deployFlags.AdditionalTargets, "extra-targets", nil, "Additional Prometheus target files")

	// Grafana
	f.StringVar(&deployFlags.AdminPassword, "admin-password", "admin", "Grafana admin password")
	f.StringVar(&deployFlags.AnonymousRole, "anonymous-role", "Admin", "Grafana anonymous user role")
	f.BoolVar(&deployFlags.Auth, "auth", false, "Enable Grafana basic authentication")
	f.BoolVar(&deployFlags.DisableAnonymous, "disable-anonymous", false, "Disable Grafana anonymous access")
	f.StringVar(&deployFlags.LDAPConfig, "ldap-config", "", "LDAP configuration file for Grafana")
	f.StringSliceVar(&deployFlags.GrafanaEnv, "grafana-env", nil, "Grafana environment variables")
	f.StringSliceVar(&deployFlags.ExtraDashboards, "extra-dashboard", nil, "Additional dashboard templates")
	f.StringVar(&deployFlags.Solution, "solution", "", "Dashboard solution set")
	f.BoolVar(&deployFlags.SupportDashboard, "support-dashboard", false, "Include support dashboards")
	f.BoolVar(&deployFlags.ClearDashboards, "clear", false, "Clear existing dashboards")

	// Components
	f.BoolVar(&deployFlags.NoLoki, "no-loki", false, "Skip Loki and Promtail")
	f.BoolVar(&deployFlags.NoAlertManager, "no-alertmanager", false, "Skip AlertManager")
	f.BoolVar(&deployFlags.NoRenderer, "no-renderer", false, "Skip Grafana image renderer")
	f.BoolVar(&deployFlags.VictoriaMetrics, "victoria-metrics", false, "Use VictoriaMetrics instead of Prometheus")

	// Docker
	f.BoolVar(&deployFlags.AutoRestart, "auto-restart", false, "Auto-restart containers")
	f.BoolVar(&deployFlags.HostNetwork, "host-network", false, "Use host networking")
	f.StringVar(&deployFlags.BindAddress, "bind-address", "", "Bind to specific IP address")
	f.StringVar(&deployFlags.DockerParam, "docker-param", "", "Docker parameter for all containers")
	f.BoolVar(&deployFlags.QuickStartup, "quick-startup", false, "Skip container health checks")
	f.StringVar(&deployFlags.Mode, "mode", "", "Deployment mode (compose)")

	// AlertManager
	f.StringVar(&deployFlags.AlertManagerConfig, "alertmanager-config", "", "Custom AlertManager config file")
	f.StringSliceVar(&deployFlags.AlertManagerOpts, "alertmanager-opt", nil, "AlertManager command line options")

	// Consul
	f.StringVar(&deployFlags.ConsulAddress, "consul-address", "", "Consul/Manager address for service discovery")
}

func runDeploy(cmd *cobra.Command, args []string) error {
	runtime, _ := docker.DetectRuntime(cmd.Context())

	opts := stack.DeployOptions{
		ScyllaVersion:  deployFlags.ScyllaVersion,
		ManagerVersion: deployFlags.ManagerVersion,
		Enterprise:     deployFlags.Enterprise,

		PrometheusImage:      "prom/prometheus:v3.9.1",
		GrafanaImage:         "grafana/grafana:12.3.2",
		AlertManagerImage:    "prom/alertmanager:v0.30.1",
		LokiImage:            "grafana/loki:3.6.4",
		PromtailImage:        "grafana/promtail:3.6.4",
		RendererImage:        "grafana/grafana-image-renderer:v5.4.0",
		VictoriaMetricsImage: "victoriametrics/victoria-metrics:v1.96.0",

		PrometheusPort:     deployFlags.PrometheusPort,
		GrafanaPort:        deployFlags.GrafanaPort,
		AlertManagerPort:   deployFlags.AlertManagerPort,
		LokiPort:           deployFlags.LokiPort,
		PromtailPort:       deployFlags.PromtailPort,
		PromtailBinaryPort: deployFlags.PromtailBinaryPort,

		DataDir:             deployFlags.DataDir,
		GrafanaDataDir:      deployFlags.GrafanaDataDir,
		LokiDataDir:         deployFlags.LokiDataDir,
		AlertManagerDataDir: deployFlags.AlertManagerDataDir,

		TargetsFile:        deployFlags.TargetsFile,
		NodeExporterFile:   deployFlags.NodeExporterFile,
		ManagerTargetsFile: deployFlags.ManagerTargetsFile,
		VectorSearchFile:   deployFlags.VectorSearchFile,
		TargetsDir:         deployFlags.TargetsDir,

		ScrapeInterval:     deployFlags.ScrapeInterval,
		EvaluationInterval: deployFlags.EvaluationInterval,
		NativeHistogram:    deployFlags.NativeHistogram,
		DropMetrics:        deployFlags.DropMetrics,
		PrometheusOpts:     deployFlags.PrometheusOpts,
		AlertRules:         deployFlags.AlertRules,
		AdditionalTargets:  deployFlags.AdditionalTargets,

		AdminPassword:    deployFlags.AdminPassword,
		AnonymousRole:    deployFlags.AnonymousRole,
		BasicAuth:        deployFlags.Auth,
		Anonymous:        !deployFlags.DisableAnonymous,
		DisableAnonymous: deployFlags.DisableAnonymous,
		LDAPConfigFile:   deployFlags.LDAPConfig,
		GrafanaEnv:       deployFlags.GrafanaEnv,
		ExtraDashboards:  deployFlags.ExtraDashboards,
		Solution:         deployFlags.Solution,
		SupportDashboard: deployFlags.SupportDashboard,
		ClearDashboards:  deployFlags.ClearDashboards,

		NoLoki:          deployFlags.NoLoki,
		NoAlertManager:  deployFlags.NoAlertManager,
		NoRenderer:      deployFlags.NoRenderer,
		VictoriaMetrics: deployFlags.VictoriaMetrics,

		AutoRestart:  deployFlags.AutoRestart,
		HostNetwork:  deployFlags.HostNetwork,
		BindAddress:  deployFlags.BindAddress,
		DockerParam:  deployFlags.DockerParam,
		QuickStartup: deployFlags.QuickStartup,

		StackID: deployFlags.StackID,

		AlertManagerConfig: deployFlags.AlertManagerConfig,
		AlertManagerOpts:   deployFlags.AlertManagerOpts,
		ConsulAddress:      deployFlags.ConsulAddress,

		Runtime: runtime,
	}

	ctx := context.Background()
	if err := stack.Deploy(ctx, opts); err != nil {
		return fmt.Errorf("deploy failed: %w", err)
	}

	fmt.Println("Monitoring stack deployed successfully.")
	return nil
}
