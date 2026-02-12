package migrate

import (
	"encoding/json"
	"fmt"
	"log/slog"

	"github.com/scylladb/scylla-monitoring/scylla-monitor-ctl/pkg/grafana"
)

// CopyOptions holds options for live stack-to-stack copy.
type CopyOptions struct {
	SourceGrafanaURL       string
	SourceGrafanaUser      string
	SourceGrafanaPassword  string
	TargetGrafanaURL       string
	TargetGrafanaUser      string
	TargetGrafanaPassword  string
	IncludeDashboards      bool
	IncludeDatasources     bool
}

// Copy performs a live copy from one Grafana to another.
func Copy(opts CopyOptions) error {
	source := grafana.NewClient(opts.SourceGrafanaURL, opts.SourceGrafanaUser, opts.SourceGrafanaPassword)
	target := grafana.NewClient(opts.TargetGrafanaURL, opts.TargetGrafanaUser, opts.TargetGrafanaPassword)

	// Copy folders
	srcFolders, err := source.ListFolders()
	if err != nil {
		return fmt.Errorf("listing source folders: %w", err)
	}
	for _, f := range srcFolders {
		if _, err := target.CreateFolder(f.Title, f.UID); err != nil {
			slog.Warn("creating folder", "folder", f.Title, "error", err)
		}
	}

	// Copy datasources
	if opts.IncludeDatasources {
		datasources, err := source.ListDatasources()
		if err != nil {
			return fmt.Errorf("listing source datasources: %w", err)
		}
		for _, ds := range datasources {
			ds.ID = 0 // Clear for create
			if err := target.CreateDatasource(ds); err != nil {
				slog.Warn("creating datasource", "datasource", ds.Name, "error", err)
			}
		}
	}

	// Copy dashboards
	if opts.IncludeDashboards {
		results, err := source.SearchDashboards()
		if err != nil {
			return fmt.Errorf("searching source dashboards: %w", err)
		}

		for _, r := range results {
			data, err := source.DownloadDashboard(r.UID)
			if err != nil {
				slog.Warn("downloading dashboard", "dashboard", r.Title, "error", err)
				continue
			}

			// Extract just the dashboard object and strip id
			var wrapper map[string]json.RawMessage
			if err := json.Unmarshal(data, &wrapper); err != nil {
				continue
			}
			dashJSON := data
			if dash, ok := wrapper["dashboard"]; ok {
				var dashObj map[string]interface{}
				if err := json.Unmarshal(dash, &dashObj); err == nil {
					delete(dashObj, "id")
					dashJSON, _ = json.Marshal(dashObj)
				}
			}

			folderID := r.FolderID
			if err := target.UploadDashboard(dashJSON, folderID, true); err != nil {
				slog.Warn("uploading dashboard", "dashboard", r.Title, "error", err)
			}
		}
	}

	return nil
}
