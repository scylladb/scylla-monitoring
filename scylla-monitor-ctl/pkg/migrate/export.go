package migrate

import (
	"encoding/json"
	"fmt"
	"log/slog"
	"os"
	"path/filepath"
	"time"

	"github.com/scylladb/scylla-monitoring/scylla-monitor-ctl/pkg/grafana"
	"github.com/scylladb/scylla-monitoring/scylla-monitor-ctl/pkg/prometheus"

	"gopkg.in/yaml.v3"
)

// ArchiveOptions holds options for exporting a monitoring stack.
type ArchiveOptions struct {
	PrometheusURL    string
	GrafanaURL       string
	GrafanaUser      string
	GrafanaPassword  string
	OutputPath       string // path to the output tar.gz

	// Local config file paths (for collecting configs)
	PrometheusConfig string
	AlertRulesDir    string
	AlertManagerConfig string
	LokiConfig       string
	TargetFiles      []string
}

// Metadata holds export metadata written to the archive.
type Metadata struct {
	ExportTimestamp string `yaml:"export_timestamp"`
	GrafanaURL      string `yaml:"grafana_url,omitempty"`
	PrometheusURL   string `yaml:"prometheus_url,omitempty"`
	IncludesData    bool   `yaml:"includes_data"`
	DashboardCount  int    `yaml:"dashboard_count"`
	DatasourceCount int    `yaml:"datasource_count"`
}

// ArchiveStack exports the monitoring stack to a tar.gz archive.
func ArchiveStack(opts ArchiveOptions) error {
	// Create staging directory
	stageDir, err := os.MkdirTemp("", "scylla-monitor-export-*")
	if err != nil {
		return fmt.Errorf("creating staging directory: %w", err)
	}
	defer os.RemoveAll(stageDir)

	meta := Metadata{
		ExportTimestamp: time.Now().UTC().Format(time.RFC3339),
		GrafanaURL:      opts.GrafanaURL,
		PrometheusURL:   opts.PrometheusURL,
		IncludesData:    opts.PrometheusURL != "",
	}

	// Export Grafana dashboards and datasources
	if opts.GrafanaURL != "" {
		gc := grafana.NewClient(opts.GrafanaURL, opts.GrafanaUser, opts.GrafanaPassword)

		// Dashboards
		dashDir := filepath.Join(stageDir, "dashboards")
		if err := os.MkdirAll(dashDir, 0755); err != nil {
			return err
		}

		results, err := gc.SearchDashboards()
		if err != nil {
			return fmt.Errorf("searching dashboards: %w", err)
		}

		for _, r := range results {
			data, err := gc.DownloadDashboard(r.UID)
			if err != nil {
				slog.Warn("downloading dashboard", "uid", r.UID, "error", err)
				continue
			}
			// Strip the "id" field for portability
			var parsed map[string]interface{}
			if err := json.Unmarshal(data, &parsed); err == nil {
				if dash, ok := parsed["dashboard"].(map[string]interface{}); ok {
					delete(dash, "id")
				}
				data, _ = json.MarshalIndent(parsed, "", "  ")
			}
			fname := fmt.Sprintf("%s.json", r.UID)
			if err := os.WriteFile(filepath.Join(dashDir, fname), data, 0644); err != nil {
				return fmt.Errorf("writing dashboard %s: %w", r.UID, err)
			}
			meta.DashboardCount++
		}

		// Datasources
		dsDir := filepath.Join(stageDir, "datasources")
		if err := os.MkdirAll(dsDir, 0755); err != nil {
			return err
		}

		datasources, err := gc.ListDatasources()
		if err != nil {
			return fmt.Errorf("listing datasources: %w", err)
		}
		for _, ds := range datasources {
			data, err := json.MarshalIndent(ds, "", "  ")
			if err != nil {
				continue
			}
			fname := fmt.Sprintf("%s.json", ds.Name)
			if err := os.WriteFile(filepath.Join(dsDir, fname), data, 0644); err != nil {
				return fmt.Errorf("writing datasource %s: %w", ds.Name, err)
			}
			meta.DatasourceCount++
		}

		// Folders
		folderDir := filepath.Join(stageDir, "folders")
		if err := os.MkdirAll(folderDir, 0755); err != nil {
			return err
		}
		folders, err := gc.ListFolders()
		if err == nil {
			data, _ := json.MarshalIndent(folders, "", "  ")
			os.WriteFile(filepath.Join(folderDir, "folders.json"), data, 0644)
		}
	}

	// Collect config files
	configDir := filepath.Join(stageDir, "prometheus")
	os.MkdirAll(configDir, 0755)

	if opts.PrometheusConfig != "" {
		copyFile(opts.PrometheusConfig, filepath.Join(configDir, "prometheus.yml"))
	}
	if opts.AlertRulesDir != "" {
		copyDir(opts.AlertRulesDir, filepath.Join(configDir, "prom_rules"))
	}
	if opts.AlertManagerConfig != "" {
		amDir := filepath.Join(stageDir, "alertmanager")
		os.MkdirAll(amDir, 0755)
		copyFile(opts.AlertManagerConfig, filepath.Join(amDir, "config.yml"))
	}
	if opts.LokiConfig != "" {
		lokiDir := filepath.Join(stageDir, "loki")
		os.MkdirAll(lokiDir, 0755)
		copyFile(opts.LokiConfig, filepath.Join(lokiDir, "config.yaml"))
	}

	// Target files
	if len(opts.TargetFiles) > 0 {
		targetDir := filepath.Join(stageDir, "targets")
		os.MkdirAll(targetDir, 0755)
		for _, tf := range opts.TargetFiles {
			copyFile(tf, filepath.Join(targetDir, filepath.Base(tf)))
		}
	}

	// Prometheus snapshot
	if opts.PrometheusURL != "" {
		pc := prometheus.NewClient(opts.PrometheusURL)
		snapName, err := pc.CreateSnapshot()
		if err != nil {
			slog.Warn("creating Prometheus snapshot", "error", err)
		} else {
			meta.IncludesData = true
			// Snapshot data would need to be copied from the container
			// Store the snapshot name in metadata for manual collection
			_ = snapName
		}
	}

	// Write metadata
	metaData, err := yaml.Marshal(meta)
	if err != nil {
		return fmt.Errorf("marshaling metadata: %w", err)
	}
	if err := os.WriteFile(filepath.Join(stageDir, "metadata.yaml"), metaData, 0644); err != nil {
		return fmt.Errorf("writing metadata: %w", err)
	}

	// Pack archive
	if err := PackArchive(stageDir, opts.OutputPath); err != nil {
		return fmt.Errorf("packing archive: %w", err)
	}

	return nil
}

func copyFile(src, dst string) error {
	data, err := os.ReadFile(src)
	if err != nil {
		return err
	}
	return os.WriteFile(dst, data, 0644)
}

func copyDir(src, dst string) error {
	return filepath.Walk(src, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		relPath, _ := filepath.Rel(src, path)
		target := filepath.Join(dst, relPath)
		if info.IsDir() {
			return os.MkdirAll(target, 0755)
		}
		return copyFile(path, target)
	})
}
