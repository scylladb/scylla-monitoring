package config

import (
	"github.com/spf13/viper"
)

// Config holds the full application configuration.
type Config struct {
	ScyllaVersion  string `mapstructure:"scylla_version"`
	ManagerVersion string `mapstructure:"manager_version"`
	Enterprise     bool   `mapstructure:"enterprise"`

	Storage struct {
		PrometheusData    string `mapstructure:"prometheus_data"`
		GrafanaData       string `mapstructure:"grafana_data"`
		LokiData          string `mapstructure:"loki_data"`
		AlertManagerData  string `mapstructure:"alertmanager_data"`
	} `mapstructure:"storage"`

	Ports struct {
		Prometheus     int `mapstructure:"prometheus"`
		Grafana        int `mapstructure:"grafana"`
		AlertManager   int `mapstructure:"alertmanager"`
		Loki           int `mapstructure:"loki"`
		Promtail       int `mapstructure:"promtail"`
		PromtailBinary int `mapstructure:"promtail_binary"`
	} `mapstructure:"ports"`

	Prometheus struct {
		ScrapeInterval     string   `mapstructure:"scrape_interval"`
		EvaluationInterval string   `mapstructure:"evaluation_interval"`
		NativeHistogram    bool     `mapstructure:"native_histogram"`
		DropMetrics        []string `mapstructure:"drop_metrics"`
		DropMetricsRegex   []string `mapstructure:"drop_metrics_regex"`
	} `mapstructure:"prometheus"`

	Auth struct {
		GrafanaAdminPassword string `mapstructure:"grafana_admin_password"`
		AnonymousRole        string `mapstructure:"anonymous_role"`
		BasicAuth            bool   `mapstructure:"basic_auth"`
		Anonymous            bool   `mapstructure:"anonymous"`
		DisableAnonymous     bool   `mapstructure:"disable_anonymous"`
		LDAPConfig           string `mapstructure:"ldap_config"`
	} `mapstructure:"auth"`

	Dashboards struct {
		List            []string `mapstructure:"list"`
		Solution        string   `mapstructure:"solution"`
		RefreshInterval string   `mapstructure:"refresh_interval"`
	} `mapstructure:"dashboards"`

	StackID int `mapstructure:"stack_id"`
}

// LoadConfig loads configuration from Viper into a Config struct.
func LoadConfig() (*Config, error) {
	var cfg Config
	if err := viper.Unmarshal(&cfg); err != nil {
		return nil, err
	}
	return &cfg, nil
}

// Defaults sets default values in Viper.
func Defaults() {
	viper.SetDefault("scylla_version", "")
	viper.SetDefault("manager_version", "")
	viper.SetDefault("enterprise", false)
	viper.SetDefault("ports.prometheus", 9090)
	viper.SetDefault("ports.grafana", 3000)
	viper.SetDefault("ports.alertmanager", 9093)
	viper.SetDefault("ports.loki", 3100)
	viper.SetDefault("ports.promtail", 9080)
	viper.SetDefault("ports.promtail_binary", 1514)
	viper.SetDefault("prometheus.scrape_interval", "20s")
	viper.SetDefault("prometheus.evaluation_interval", "20s")
	viper.SetDefault("auth.grafana_admin_password", "admin")
	viper.SetDefault("auth.anonymous_role", "Admin")
	viper.SetDefault("auth.basic_auth", false)
	viper.SetDefault("auth.anonymous", true)
	viper.SetDefault("auth.disable_anonymous", false)
	viper.SetDefault("auth.ldap_config", "")
	viper.SetDefault("dashboards.refresh_interval", "5m")
	viper.SetDefault("stack_id", 0)
}
