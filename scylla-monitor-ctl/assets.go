package main

import "embed"

//go:embed assets/grafana/types.json
var typesJSON []byte

//go:embed assets/grafana/*.template.json
var dashboardTemplates embed.FS

//go:embed assets/prometheus/prometheus.yml.template
var prometheusTemplate []byte

//go:embed assets/prometheus/prometheus.consul.yml.template
var prometheusConsulTemplate []byte

//go:embed assets/prometheus/prom_rules/*.yml
var alertRules embed.FS

//go:embed assets/grafana/datasource.yml
var datasourceTemplate []byte

//go:embed assets/grafana/datasource.loki.yml
var datasourceLokiTemplate []byte

//go:embed assets/grafana/datasource.scylla.yml
var datasourceScyllaTemplate []byte

//go:embed assets/grafana/load.yaml
var loadTemplate []byte

//go:embed assets/loki/conf/loki-config.template.yaml
var lokiConfigTemplate []byte

//go:embed assets/loki/promtail/promtail_config.template.yml
var promtailConfigTemplate []byte

//go:embed assets/alertmanager/rule_config.yml
var alertmanagerDefaultConfig []byte

//go:embed assets/docker-compose.template.yml
var composeTemplate []byte

//go:embed assets/versions.yaml
var versionsData []byte
