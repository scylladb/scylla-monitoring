package cmd

import (
	"fmt"
	"os"
	"path/filepath"

	"github.com/scylladb/scylla-monitoring/scylla-monitor-ctl/pkg/targets"
	"github.com/spf13/cobra"
)

var targetsGenFlags struct {
	Targets        []string
	Cluster        string
	Output         string
	FromNodetool   bool
	AliasSeparator string
}

var targetsCmd = &cobra.Command{
	Use:   "targets",
	Short: "Target file management",
}

var targetsGenerateCmd = &cobra.Command{
	Use:   "generate",
	Short: "Generate Prometheus target YAML from node list",
	RunE:  runTargetsGenerate,
}

func runTargetsGenerate(cmd *cobra.Command, args []string) error {
	output := targetsGenFlags.Output
	if output == "" {
		output = "scylla_servers.yml"
	}

	dir := filepath.Dir(output)
	filename := filepath.Base(output)

	var servers []string

	if targetsGenFlags.FromNodetool {
		// Read from stdin
		parsed, err := targets.ParseNodetoolStatus(os.Stdin)
		if err != nil {
			return fmt.Errorf("parsing nodetool status: %w", err)
		}
		servers = parsed
	} else if len(targetsGenFlags.Targets) > 0 {
		servers = targetsGenFlags.Targets
	} else if len(args) > 0 {
		// Plain IP list (no DC labels)
		return targets.WriteTargetsSimple(args, dir, filename)
	} else {
		return fmt.Errorf("either --targets, --from-nodetool, or positional arguments are required")
	}

	groups, err := targets.GenerateTargets(servers, targetsGenFlags.Cluster, targetsGenFlags.AliasSeparator)
	if err != nil {
		return fmt.Errorf("generating targets: %w", err)
	}

	if err := targets.WriteTargetsFile(groups, dir, filename); err != nil {
		return fmt.Errorf("writing targets: %w", err)
	}

	fmt.Printf("Wrote targets to %s\n", output)
	return nil
}

func init() {
	f := targetsGenerateCmd.Flags()
	f.StringSliceVar(&targetsGenFlags.Targets, "targets", nil, "target list in dc:ip1,ip2 format")
	f.StringVar(&targetsGenFlags.Cluster, "cluster", "my-cluster", "cluster name")
	f.StringVar(&targetsGenFlags.Output, "output", "scylla_servers.yml", "output file path")
	f.BoolVar(&targetsGenFlags.FromNodetool, "from-nodetool", false, "read nodetool status from stdin")
	f.StringVar(&targetsGenFlags.AliasSeparator, "alias-separator", "", "separator for IP=alias format")

	targetsCmd.AddCommand(targetsGenerateCmd)
	rootCmd.AddCommand(targetsCmd)
}
