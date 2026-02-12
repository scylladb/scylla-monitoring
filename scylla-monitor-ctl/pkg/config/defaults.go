package config

// DefaultDashboards is the default set of dashboards to generate.
var DefaultDashboards = []string{
	"scylla-overview",
	"scylla-detailed",
	"scylla-os",
	"scylla-cql",
	"scylla-advanced",
	"alternator",
	"scylla-ks",
}

// DefaultPorts holds default port assignments.
var DefaultPorts = struct {
	Prometheus     int
	Grafana        int
	AlertManager   int
	Loki           int
	Promtail       int
	PromtailBinary int
}{
	Prometheus:     9090,
	Grafana:        3000,
	AlertManager:   9093,
	Loki:           3100,
	Promtail:       9080,
	PromtailBinary: 1514,
}
