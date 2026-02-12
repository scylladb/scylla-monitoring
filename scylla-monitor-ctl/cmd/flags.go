package cmd

import "github.com/spf13/cobra"

// GrafanaConnFlags defines Grafana connection flags (URL, user, password).
type GrafanaConnFlags struct {
	URL      string
	User     string
	Password string
}

// Register adds grafana-url, grafana-user, grafana-password flags to cmd.
// urlDefault is the default value for grafana-url (e.g. "http://localhost:3000" or "").
func (f *GrafanaConnFlags) Register(cmd *cobra.Command, urlDefault string) {
	cmd.Flags().StringVar(&f.URL, "grafana-url", urlDefault, "Grafana URL")
	cmd.Flags().StringVar(&f.User, "grafana-user", "admin", "Grafana user")
	cmd.Flags().StringVar(&f.Password, "grafana-password", "admin", "Grafana password")
}

// RegisterWithPrefix adds prefixed grafana flags (e.g. "source-grafana-url").
func (f *GrafanaConnFlags) RegisterWithPrefix(cmd *cobra.Command, prefix, description string) {
	cmd.Flags().StringVar(&f.URL, prefix+"grafana-url", "", description+" Grafana URL")
	cmd.Flags().StringVar(&f.User, prefix+"grafana-user", "admin", description+" Grafana user")
	cmd.Flags().StringVar(&f.Password, prefix+"grafana-password", "admin", description+" Grafana password")
}

// StackPortFlags defines stack ID and component port flags.
type StackPortFlags struct {
	StackID          int
	PrometheusPort   int
	GrafanaPort      int
	AlertManagerPort int
	LokiPort         int
	PromtailPort     int
}

// Register adds stack and port flags to cmd.
func (f *StackPortFlags) Register(cmd *cobra.Command) {
	cmd.Flags().IntVar(&f.StackID, "stack", 0, "Stack ID (0=primary, 1-4=secondary)")
	cmd.Flags().IntVar(&f.PrometheusPort, "prometheus-port", 9090, "Prometheus port")
	cmd.Flags().IntVar(&f.GrafanaPort, "grafana-port", 3000, "Grafana port")
	cmd.Flags().IntVar(&f.AlertManagerPort, "alertmanager-port", 9093, "AlertManager port")
	cmd.Flags().IntVar(&f.LokiPort, "loki-port", 3100, "Loki port")
	cmd.Flags().IntVar(&f.PromtailPort, "promtail-port", 9080, "Promtail port")
}

// VersionFlags defines ScyllaDB and Manager version flags.
type VersionFlags struct {
	ScyllaVersion  string
	ManagerVersion string
}

// Register adds scylla-version and manager-version flags to cmd.
func (f *VersionFlags) Register(cmd *cobra.Command) {
	cmd.Flags().StringVar(&f.ScyllaVersion, "scylla-version", "", "ScyllaDB version")
	cmd.Flags().StringVar(&f.ManagerVersion, "manager-version", "", "Scylla Manager version")
}
