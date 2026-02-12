package cmd

import (
	"fmt"
	"log/slog"
	"os"

	"github.com/spf13/cobra"
	"github.com/spf13/viper"
)

var cfgFile string

var rootCmd = &cobra.Command{
	Use:   "scylla-monitor-ctl",
	Short: "ScyllaDB Monitoring Stack management tool",
	Long:  `A single binary that manages the ScyllaDB monitoring stack: dashboards, Prometheus, Grafana, AlertManager, and Loki.`,
	PersistentPreRun: func(cmd *cobra.Command, args []string) {
		initLogging(cmd)
	},
}

func Execute() {
	if err := rootCmd.Execute(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func init() {
	cobra.OnInitialize(initConfig)
	rootCmd.PersistentFlags().StringVar(&cfgFile, "config", "", "config file (default is ./scylla-monitor.yaml)")
	rootCmd.PersistentFlags().Bool("verbose", false, "verbose output")
	rootCmd.PersistentFlags().Bool("quiet", false, "suppress non-essential output")
	rootCmd.PersistentFlags().Bool("dry-run", false, "preview actions without executing")
}

func initLogging(cmd *cobra.Command) {
	level := slog.LevelInfo
	if v, _ := cmd.Flags().GetBool("verbose"); v {
		level = slog.LevelDebug
	} else if q, _ := cmd.Flags().GetBool("quiet"); q {
		level = slog.LevelError
	}
	handler := slog.NewTextHandler(os.Stderr, &slog.HandlerOptions{Level: level})
	slog.SetDefault(slog.New(handler))
}

func initConfig() {
	if cfgFile != "" {
		viper.SetConfigFile(cfgFile)
	} else {
		viper.SetConfigName("scylla-monitor")
		viper.SetConfigType("yaml")
		viper.AddConfigPath(".")
	}
	viper.AutomaticEnv()
	_ = viper.ReadInConfig()
}
