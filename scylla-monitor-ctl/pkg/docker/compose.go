package docker

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// ComposeOptions holds options for generating docker-compose.yml and .env files.
type ComposeOptions struct {
	Template          []byte
	OutputDir         string
	PrometheusVersion string
	AlertManagerVersion string
	GrafanaVersion    string
	LokiVersion       string
	PrometheusPort    int
	GrafanaPort       int
	AlertManagerPort  int
	LokiPort          int
	AdminPassword     string
	BasicAuth         bool
	Anonymous         bool
	AnonymousRole     string
	ScyllaTargetFile  string
	NodeTargetFile    string
	PrometheusRules   string
	PrometheusCmd     []string
	GrafanaEnv        []string
	DockerParams      string
	RestartPolicy     string
	HostNetwork       bool
	PrometheusDataDir string
	GrafanaDataDir    string
	AlertManagerDataDir string
	LokiDataDir       string
	RunLoki           bool
	VictoriaMetrics   bool
}

// GenerateCompose generates docker-compose.yml and .env files from a template.
func GenerateCompose(opts ComposeOptions) error {
	if err := os.MkdirAll(opts.OutputDir, 0755); err != nil {
		return fmt.Errorf("creating output directory: %w", err)
	}

	compose := string(opts.Template)

	// Build prometheus command line
	if len(opts.PrometheusCmd) > 0 {
		cmdStr := ""
		for _, c := range opts.PrometheusCmd {
			cmdStr += fmt.Sprintf("      - '%s'\n", c)
		}
		compose = strings.ReplaceAll(compose, "#PROMETHEUS_COMMAND_LINE", cmdStr)
	} else {
		compose = strings.ReplaceAll(compose, "#PROMETHEUS_COMMAND_LINE", "")
	}

	// Build grafana env
	if len(opts.GrafanaEnv) > 0 {
		envStr := ""
		for _, e := range opts.GrafanaEnv {
			envStr += fmt.Sprintf("      - %s\n", e)
		}
		compose = strings.ReplaceAll(compose, "#GRAFANA_ENV", envStr)
	} else {
		compose = strings.ReplaceAll(compose, "#GRAFANA_ENV", "")
	}

	// Docker params (restart, network)
	var generalConfig string
	if opts.RestartPolicy != "" {
		generalConfig += fmt.Sprintf("    restart: %s\n", opts.RestartPolicy)
	}
	if opts.HostNetwork {
		generalConfig += "    network_mode: host\n"
	}
	compose = strings.ReplaceAll(compose, "#GENERAL_DOCER_CONFIG", generalConfig)

	// Data directories
	compose = strings.ReplaceAll(compose, "#ALERT_MANAGER_DIR", opts.AlertManagerDataDir)
	compose = strings.ReplaceAll(compose, "#LOKI_DIR", opts.LokiDataDir)

	// Write compose file
	composePath := filepath.Join(opts.OutputDir, "docker-compose.yml")
	if err := os.WriteFile(composePath, []byte(compose), 0644); err != nil {
		return fmt.Errorf("writing docker-compose.yml: %w", err)
	}

	// Write .env file
	env := generateEnvFile(opts)
	envPath := filepath.Join(opts.OutputDir, ".env")
	if err := os.WriteFile(envPath, []byte(env), 0644); err != nil {
		return fmt.Errorf("writing .env: %w", err)
	}

	return nil
}

func generateEnvFile(opts ComposeOptions) string {
	var lines []string
	add := func(k, v string) { lines = append(lines, fmt.Sprintf("%s=%s", k, v)) }

	add("PROMETHEUS_VERSION", opts.PrometheusVersion)
	add("ALERT_MANAGER_VERSION", opts.AlertManagerVersion)
	add("GRAFANA_VERSION", opts.GrafanaVersion)
	add("LOKI_VERSION", opts.LokiVersion)
	add("PROMETHEUS_PORT", fmt.Sprintf("%d", opts.PrometheusPort))
	add("GRAFANA_PORT", fmt.Sprintf("%d", opts.GrafanaPort))
	add("ALERTMANAGER_PORT", fmt.Sprintf("%d", opts.AlertManagerPort))
	add("LOKI_PORT", fmt.Sprintf("%d", opts.LokiPort))
	add("GF_AUTH_BASIC_ENABLED", fmt.Sprintf("%t", opts.BasicAuth))
	add("GF_AUTH_ANONYMOUS_ENABLED", fmt.Sprintf("%t", opts.Anonymous))
	add("GF_AUTH_ANONYMOUS_ORG_ROLE", opts.AnonymousRole)
	add("GF_SECURITY_ADMIN_PASSWORD", opts.AdminPassword)

	if opts.ScyllaTargetFile != "" {
		add("SCYLLA_TARGET_FILE", opts.ScyllaTargetFile)
	}
	if opts.NodeTargetFile != "" {
		add("NODE_TARGET_FILE", opts.NodeTargetFile)
	}
	if opts.PrometheusRules != "" {
		add("PROMETHEUS_RULES", opts.PrometheusRules)
	}

	return strings.Join(lines, "\n") + "\n"
}
