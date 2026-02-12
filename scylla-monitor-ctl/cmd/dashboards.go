package cmd

import (
	"encoding/json"
	"fmt"
	"log/slog"
	"os"
	"path/filepath"

	"github.com/scylladb/scylla-monitoring/scylla-monitor-ctl/pkg/dashboard"
	"github.com/scylladb/scylla-monitoring/scylla-monitor-ctl/pkg/grafana"
	"github.com/spf13/cobra"
)

var dashGenFlags struct {
	VersionFlags
	OutputDir       string
	Force           bool
	Dashboards      []string
	RefreshInterval string
	Types           []string
	ReplaceFiles    []string
	Replace         []string
	Products        []string
}

var dashUploadFlags struct {
	GrafanaConnFlags
	FolderID  int
	Overwrite bool
}

var dashDownloadFlags struct {
	GrafanaConnFlags
	OutputDir string
}

var dashListFlags struct {
	GrafanaConnFlags
}

var dashboardsCmd = &cobra.Command{
	Use:   "dashboards",
	Short: "Dashboard generation and management",
}

var dashboardsGenerateCmd = &cobra.Command{
	Use:   "generate",
	Short: "Generate dashboard JSON files from templates",
	RunE:  runDashboardsGenerate,
}

func runDashboardsGenerate(cmd *cobra.Command, args []string) error {
	scyllaVersion := dashGenFlags.ScyllaVersion
	managerVersion := dashGenFlags.ManagerVersion
	outputDir := dashGenFlags.OutputDir
	dashboardList := dashGenFlags.Dashboards
	typesFiles := dashGenFlags.Types

	if scyllaVersion == "" {
		return fmt.Errorf("--scylla-version is required")
	}

	if outputDir == "" {
		outputDir = "grafana/build"
	}

	if len(dashboardList) == 0 {
		dashboardList = []string{"scylla-overview", "scylla-detailed", "scylla-os", "scylla-cql", "scylla-advanced", "alternator", "scylla-ks"}
	}

	if len(typesFiles) == 0 {
		typesFiles = []string{"grafana/types.json"}
	}

	// Load and merge types files
	types, err := dashboard.MergeTypesFiles(typesFiles)
	if err != nil {
		return fmt.Errorf("loading types: %w", err)
	}

	typesJSON, err := json.Marshal(types)
	if err != nil {
		return fmt.Errorf("marshaling types: %w", err)
	}

	gen, err := dashboard.NewGenerator(typesJSON)
	if err != nil {
		return fmt.Errorf("creating generator: %w", err)
	}

	gen.SetVersion(scyllaVersion)
	gen.Products = dashGenFlags.Products

	if len(dashGenFlags.ReplaceFiles) > 0 {
		exactMatch, err := dashboard.LoadExactMatchFiles(dashGenFlags.ReplaceFiles)
		if err != nil {
			return fmt.Errorf("loading replace files: %w", err)
		}
		gen.ExactMatch = exactMatch
	}

	// Build replacement strings
	replacements := dashboard.ParseReplacements(dashGenFlags.Replace)
	replacements = append(replacements, [2]string{"__SCYLLA_VERSION_DOT__", scyllaVersion})
	replacements = append(replacements, [2]string{"__MONITOR_VERSION__", MonitorVersion})
	if dashGenFlags.RefreshInterval != "" {
		replacements = append(replacements, [2]string{"__REFRESH_INTERVAL__", dashGenFlags.RefreshInterval})
	}
	gen.SetReplacements(replacements)

	versionDir := filepath.Join(outputDir, "ver_"+scyllaVersion)

	for _, d := range dashboardList {
		templatePath := fmt.Sprintf("grafana/%s.template.json", d)
		outputPath := filepath.Join(versionDir, fmt.Sprintf("%s.%s.json", d, scyllaVersion))

		if !dashGenFlags.Force && !needsRegeneration(templatePath, outputPath) {
			fmt.Printf("  Skipping %s (up to date)\n", d)
			continue
		}

		templateData, err := os.ReadFile(templatePath)
		if err != nil {
			return fmt.Errorf("reading template %s: %w", templatePath, err)
		}

		if err := gen.GenerateToFile(templateData, outputPath); err != nil {
			return fmt.Errorf("generating %s: %w", d, err)
		}

		fmt.Printf("  Generated %s\n", outputPath)
	}

	// Generate manager dashboards if requested
	if managerVersion != "" {
		managerDir := filepath.Join(outputDir, "manager_"+managerVersion)
		for _, d := range []string{"scylla-manager"} {
			templatePath := fmt.Sprintf("grafana/%s.template.json", d)
			outputPath := filepath.Join(managerDir, fmt.Sprintf("%s.%s.json", d, managerVersion))

			if !dashGenFlags.Force && !needsRegeneration(templatePath, outputPath) {
				fmt.Printf("  Skipping %s (up to date)\n", d)
				continue
			}

			templateData, err := os.ReadFile(templatePath)
			if err != nil {
				fmt.Printf("  Skipping %s (template not found)\n", d)
				continue
			}

			if err := gen.GenerateToFile(templateData, outputPath); err != nil {
				return fmt.Errorf("generating %s: %w", d, err)
			}

			fmt.Printf("  Generated %s\n", outputPath)
		}
	}

	fmt.Println("Dashboard generation complete.")
	return nil
}

var dashboardsUploadCmd = &cobra.Command{
	Use:   "upload [files...]",
	Short: "Upload dashboard JSON files to Grafana",
	Args:  cobra.MinimumNArgs(1),
	RunE:  runDashboardsUpload,
}

var dashboardsDownloadCmd = &cobra.Command{
	Use:   "download [uid...]",
	Short: "Download dashboards from Grafana",
	Long:  `Download all dashboards (no args) or specific dashboards by UID.`,
	RunE:  runDashboardsDownload,
}

var dashboardsListCmd = &cobra.Command{
	Use:   "list",
	Short: "List dashboards in Grafana",
	RunE:  runDashboardsList,
}

func runDashboardsUpload(cmd *cobra.Command, args []string) error {
	gc := grafana.NewClient(dashUploadFlags.URL, dashUploadFlags.User, dashUploadFlags.Password)

	for _, path := range args {
		data, err := os.ReadFile(path)
		if err != nil {
			return fmt.Errorf("reading %s: %w", path, err)
		}
		if err := gc.UploadDashboard(data, dashUploadFlags.FolderID, dashUploadFlags.Overwrite); err != nil {
			slog.Warn("uploading dashboard", "path", path, "error", err)
			continue
		}
		fmt.Printf("Uploaded %s\n", path)
	}
	return nil
}

func runDashboardsDownload(cmd *cobra.Command, args []string) error {
	gc := grafana.NewClient(dashDownloadFlags.URL, dashDownloadFlags.User, dashDownloadFlags.Password)
	outputDir := dashDownloadFlags.OutputDir

	if err := os.MkdirAll(outputDir, 0755); err != nil {
		return fmt.Errorf("creating output directory: %w", err)
	}

	if len(args) > 0 {
		// Download specific dashboards by UID
		for _, uid := range args {
			data, err := gc.DownloadDashboard(uid)
			if err != nil {
				slog.Warn("downloading dashboard", "uid", uid, "error", err)
				continue
			}
			outPath := filepath.Join(outputDir, uid+".json")
			if err := os.WriteFile(outPath, data, 0644); err != nil {
				return fmt.Errorf("writing %s: %w", outPath, err)
			}
			fmt.Printf("Downloaded %s\n", outPath)
		}
	} else {
		// Download all dashboards
		results, err := gc.SearchDashboards()
		if err != nil {
			return fmt.Errorf("searching dashboards: %w", err)
		}
		for _, r := range results {
			data, err := gc.DownloadDashboard(r.UID)
			if err != nil {
				slog.Warn("downloading dashboard", "dashboard", r.Title, "error", err)
				continue
			}
			outPath := filepath.Join(outputDir, r.UID+".json")
			if err := os.WriteFile(outPath, data, 0644); err != nil {
				return fmt.Errorf("writing %s: %w", outPath, err)
			}
			fmt.Printf("Downloaded %s (%s)\n", r.Title, outPath)
		}
	}
	return nil
}

func runDashboardsList(cmd *cobra.Command, args []string) error {
	gc := grafana.NewClient(dashListFlags.URL, dashListFlags.User, dashListFlags.Password)

	results, err := gc.SearchDashboards()
	if err != nil {
		return fmt.Errorf("searching dashboards: %w", err)
	}

	fmt.Printf("%-40s %-20s %s\n", "Title", "UID", "Folder")
	for _, r := range results {
		folder := fmt.Sprintf("id:%d", r.FolderID)
		if r.FolderUID != "" {
			folder = r.FolderUID
		}
		fmt.Printf("%-40s %-20s %s\n", r.Title, r.UID, folder)
	}
	return nil
}

func needsRegeneration(templatePath, outputPath string) bool {
	templateInfo, err := os.Stat(templatePath)
	if err != nil {
		return true
	}
	outputInfo, err := os.Stat(outputPath)
	if err != nil {
		return true
	}
	return templateInfo.ModTime().After(outputInfo.ModTime())
}

func init() {
	// Generate flags
	dashGenFlags.VersionFlags.Register(dashboardsGenerateCmd)
	gf := dashboardsGenerateCmd.Flags()
	gf.StringVar(&dashGenFlags.OutputDir, "output-dir", "", "output directory (default: grafana/build)")
	gf.BoolVar(&dashGenFlags.Force, "force", false, "force regeneration even if up to date")
	gf.StringSliceVar(&dashGenFlags.Dashboards, "dashboards", nil, "dashboards to generate (comma-separated)")
	gf.StringVar(&dashGenFlags.RefreshInterval, "refresh-interval", "5m", "dashboard refresh interval")
	gf.StringSliceVar(&dashGenFlags.Types, "types", nil, "types files (default: grafana/types.json)")
	gf.StringSliceVar(&dashGenFlags.ReplaceFiles, "replace-file", nil, "exact match replacement files")
	gf.StringSliceVar(&dashGenFlags.Replace, "replace", nil, "replacement strings (key=value)")
	gf.StringSliceVar(&dashGenFlags.Products, "product", nil, "product filters")

	// Upload flags
	dashUploadFlags.GrafanaConnFlags.Register(dashboardsUploadCmd, "http://localhost:3000")
	uf := dashboardsUploadCmd.Flags()
	uf.IntVar(&dashUploadFlags.FolderID, "folder-id", 0, "Grafana folder ID")
	uf.BoolVar(&dashUploadFlags.Overwrite, "overwrite", true, "Overwrite existing dashboards")

	// Download flags
	dashDownloadFlags.GrafanaConnFlags.Register(dashboardsDownloadCmd, "http://localhost:3000")
	dashboardsDownloadCmd.Flags().StringVar(&dashDownloadFlags.OutputDir, "output-dir", ".", "Output directory for downloaded dashboards")

	// List flags
	dashListFlags.GrafanaConnFlags.Register(dashboardsListCmd, "http://localhost:3000")

	dashboardsCmd.AddCommand(dashboardsGenerateCmd)
	dashboardsCmd.AddCommand(dashboardsUploadCmd)
	dashboardsCmd.AddCommand(dashboardsDownloadCmd)
	dashboardsCmd.AddCommand(dashboardsListCmd)

	rootCmd.AddCommand(dashboardsCmd)
}
