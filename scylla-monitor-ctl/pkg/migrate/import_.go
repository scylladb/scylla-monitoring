package migrate

import (
	"encoding/json"
	"fmt"
	"log/slog"
	"os"
	"path/filepath"

	"github.com/scylladb/scylla-monitoring/scylla-monitor-ctl/pkg/grafana"

	"gopkg.in/yaml.v3"
)

// RestoreOptions holds options for importing a monitoring stack from an archive.
type RestoreOptions struct {
	ArchivePath     string
	DataDir         string // where to place Prometheus data
	GrafanaDataDir  string
	GrafanaURL      string
	GrafanaUser     string
	GrafanaPassword string
	GrafanaPort     int
}

// RestoreStack restores a monitoring stack from an export archive.
func RestoreStack(opts RestoreOptions) error {
	// Extract archive
	extractDir, err := os.MkdirTemp("", "scylla-monitor-import-*")
	if err != nil {
		return fmt.Errorf("creating extract directory: %w", err)
	}
	defer os.RemoveAll(extractDir)

	if err := UnpackArchive(opts.ArchivePath, extractDir); err != nil {
		return fmt.Errorf("unpacking archive: %w", err)
	}

	// Read metadata
	metaPath := filepath.Join(extractDir, "metadata.yaml")
	metaData, err := os.ReadFile(metaPath)
	if err != nil {
		return fmt.Errorf("reading metadata: %w", err)
	}
	var meta Metadata
	if err := yaml.Unmarshal(metaData, &meta); err != nil {
		return fmt.Errorf("parsing metadata: %w", err)
	}

	fmt.Printf("Importing export from %s (%d dashboards, %d datasources)\n",
		meta.ExportTimestamp, meta.DashboardCount, meta.DatasourceCount)

	// Copy config files to local paths
	promConfigSrc := filepath.Join(extractDir, "prometheus", "prometheus.yml")
	if _, err := os.Stat(promConfigSrc); err == nil {
		os.MkdirAll("prometheus/build", 0755)
		copyFile(promConfigSrc, "prometheus/build/prometheus.yml")
	}

	rulesDir := filepath.Join(extractDir, "prometheus", "prom_rules")
	if _, err := os.Stat(rulesDir); err == nil {
		copyDir(rulesDir, "prometheus/prom_rules")
	}

	amConfigSrc := filepath.Join(extractDir, "alertmanager", "config.yml")
	if _, err := os.Stat(amConfigSrc); err == nil {
		copyFile(amConfigSrc, "prometheus/rule_config.yml")
	}

	// Copy target files
	targetsDir := filepath.Join(extractDir, "targets")
	if _, err := os.Stat(targetsDir); err == nil {
		entries, _ := os.ReadDir(targetsDir)
		os.MkdirAll("prometheus", 0755)
		for _, e := range entries {
			copyFile(filepath.Join(targetsDir, e.Name()), filepath.Join("prometheus", e.Name()))
		}
	}

	// Upload dashboards and datasources to Grafana if URL provided
	if opts.GrafanaURL != "" {
		gc := grafana.NewClient(opts.GrafanaURL, opts.GrafanaUser, opts.GrafanaPassword)

		// Wait for Grafana to be ready
		if err := gc.Health(); err != nil {
			return fmt.Errorf("Grafana not ready: %w", err)
		}

		// Import datasources
		dsDir := filepath.Join(extractDir, "datasources")
		if entries, err := os.ReadDir(dsDir); err == nil {
			for _, e := range entries {
				data, err := os.ReadFile(filepath.Join(dsDir, e.Name()))
				if err != nil {
					continue
				}
				var ds grafana.APIDatasource
				if err := json.Unmarshal(data, &ds); err != nil {
					continue
				}
				ds.ID = 0 // Clear ID for create
				if err := gc.CreateDatasource(ds); err != nil {
					slog.Warn("creating datasource", "datasource", ds.Name, "error", err)
				}
			}
		}

		// Import dashboards
		dashDir := filepath.Join(extractDir, "dashboards")
		if entries, err := os.ReadDir(dashDir); err == nil {
			for _, e := range entries {
				data, err := os.ReadFile(filepath.Join(dashDir, e.Name()))
				if err != nil {
					continue
				}
				// Extract the dashboard object from the wrapper
				var wrapper map[string]json.RawMessage
				if err := json.Unmarshal(data, &wrapper); err != nil {
					continue
				}
				dashJSON := data
				if dash, ok := wrapper["dashboard"]; ok {
					dashJSON = dash
				}
				if err := gc.UploadDashboard(dashJSON, 0, true); err != nil {
					slog.Warn("uploading dashboard", "file", e.Name(), "error", err)
				}
			}
		}
	}

	return nil
}
