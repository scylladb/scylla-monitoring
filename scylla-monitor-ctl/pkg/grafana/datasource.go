package grafana

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// DatasourceOptions holds options for generating Grafana datasource provisioning files.
type DatasourceOptions struct {
	PrometheusAddress    string // e.g. "aprom:9090"
	AlertManagerAddress  string // e.g. "aalert:9093"
	LokiAddress          string // e.g. "loki:3100" (empty to skip)
	ScyllaUser           string // optional CQL credentials
	ScyllaPassword       string
	ScrapeInterval       string // override timeInterval in datasource (e.g. "30")
	StackID              int    // 0 = default path, >0 = stack-specific path
	OutputBaseDir        string // base directory (default: "grafana")
}

// outputDir returns the provisioning datasources directory for the given options.
func (o *DatasourceOptions) outputDir() string {
	base := o.OutputBaseDir
	if base == "" {
		base = "grafana"
	}
	if o.StackID > 0 {
		return filepath.Join(base, fmt.Sprintf("stack/%d/provisioning/datasources", o.StackID))
	}
	return filepath.Join(base, "provisioning/datasources")
}

// WriteDatasourceFiles generates all Grafana datasource provisioning files.
func WriteDatasourceFiles(templates DatasourceTemplates, opts DatasourceOptions) error {
	outDir := opts.outputDir()
	if err := os.MkdirAll(outDir, 0755); err != nil {
		return fmt.Errorf("creating datasource directory: %w", err)
	}

	// Main datasource (prometheus + alertmanager)
	ds := string(templates.Main)
	ds = strings.ReplaceAll(ds, "DB_ADDRESS", opts.PrometheusAddress)
	ds = strings.ReplaceAll(ds, "AM_ADDRESS", opts.AlertManagerAddress)
	if opts.ScrapeInterval != "" {
		ds = replaceDatasourceTimeInterval(ds, opts.ScrapeInterval)
	}
	if err := os.WriteFile(filepath.Join(outDir, "datasource.yaml"), []byte(ds), 0644); err != nil {
		return fmt.Errorf("writing datasource.yaml: %w", err)
	}

	// Loki datasource
	lokiPath := filepath.Join(outDir, "datasource.loki.yaml")
	if opts.LokiAddress != "" {
		loki := string(templates.Loki)
		loki = strings.ReplaceAll(loki, "LOKI_ADDRESS", opts.LokiAddress)
		if err := os.WriteFile(lokiPath, []byte(loki), 0644); err != nil {
			return fmt.Errorf("writing datasource.loki.yaml: %w", err)
		}
	} else {
		_ = os.Remove(lokiPath)
	}

	// ScyllaDB datasource
	var scyllaData []byte
	if opts.ScyllaUser != "" && opts.ScyllaPassword != "" {
		scylla := string(templates.ScyllaPassword)
		scylla = strings.ReplaceAll(scylla, "SCYLLA_USER", opts.ScyllaUser)
		scylla = strings.ReplaceAll(scylla, "SCYLLA_PSSWD", opts.ScyllaPassword)
		scyllaData = []byte(scylla)
	} else {
		scyllaData = templates.Scylla
	}
	if err := os.WriteFile(filepath.Join(outDir, "datasource.scylla.yml"), scyllaData, 0644); err != nil {
		return fmt.Errorf("writing datasource.scylla.yml: %w", err)
	}

	return nil
}

// DatasourceTemplates holds the raw template bytes for each datasource file.
type DatasourceTemplates struct {
	Main           []byte // datasource.yml
	Loki           []byte // datasource.loki.yml
	Scylla         []byte // datasource.scylla.yml
	ScyllaPassword []byte // datasource.psswd.scylla.yml
}

func replaceDatasourceTimeInterval(ds, interval string) string {
	// The template has: timeInterval: '20s'
	// Replace with the user's interval (add 's' suffix if numeric)
	replacement := interval
	if _, err := fmt.Sscanf(interval, "%d", new(int)); err == nil {
		replacement = interval + "s"
	}
	return strings.Replace(ds, "timeInterval: '20s'", "timeInterval: '"+replacement+"'", 1)
}
