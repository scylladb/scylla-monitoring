package grafana

import (
	"fmt"
	"os"
	"path/filepath"
)

// GrafanaConfig holds the Docker container configuration for Grafana.
// Used by the container orchestrator (pkg/stack/) to build docker run args.
type GrafanaConfig struct {
	EnvVars      map[string]string // -e KEY=VALUE
	VolumeMounts []VolumeMount     // -v src:dst
}

// VolumeMount represents a Docker volume bind mount.
type VolumeMount struct {
	Source   string
	Target   string
	ReadOnly bool
}

// GrafanaOptions holds all options that affect Grafana container configuration.
type GrafanaOptions struct {
	AdminPassword    string
	AnonymousRole    string // Admin, Editor, Viewer
	BasicAuth        bool
	Anonymous        bool
	LDAPConfigFile   string // path to LDAP TOML config file (empty = no LDAP)
	DisableAnonymous bool
}

// NewConfig builds the Grafana container configuration from options.
// The returned config contains env vars and volume mounts ready for the
// container orchestrator.
func NewConfig(opts GrafanaOptions) (*GrafanaConfig, error) {
	cfg := &GrafanaConfig{
		EnvVars: make(map[string]string),
	}

	// Auth defaults
	basicAuth := opts.BasicAuth
	anonymous := opts.Anonymous
	anonymousRole := opts.AnonymousRole
	if anonymousRole == "" {
		anonymousRole = "Admin"
	}

	// LDAP overrides auth settings
	if opts.LDAPConfigFile != "" {
		absPath, err := filepath.Abs(opts.LDAPConfigFile)
		if err != nil {
			return nil, fmt.Errorf("resolving LDAP config path: %w", err)
		}
		if _, err := os.Stat(absPath); err != nil {
			return nil, fmt.Errorf("LDAP config file not found: %w", err)
		}

		cfg.EnvVars["GF_AUTH_LDAP_ENABLED"] = "true"
		cfg.EnvVars["GF_AUTH_LDAP_CONFIG_FILE"] = "/etc/grafana/ldap.toml"
		cfg.EnvVars["GF_AUTH_LDAP_ALLOW_SIGN_UP"] = "true"
		cfg.VolumeMounts = append(cfg.VolumeMounts, VolumeMount{
			Source:   absPath,
			Target:   "/etc/grafana/ldap.toml",
			ReadOnly: true,
		})

		// LDAP forces basic auth on and anonymous off
		basicAuth = true
		anonymous = false
	}

	if opts.DisableAnonymous {
		anonymous = false
	}

	cfg.EnvVars["GF_AUTH_BASIC_ENABLED"] = fmt.Sprintf("%t", basicAuth)
	cfg.EnvVars["GF_AUTH_ANONYMOUS_ENABLED"] = fmt.Sprintf("%t", anonymous)
	cfg.EnvVars["GF_AUTH_ANONYMOUS_ORG_ROLE"] = anonymousRole

	if opts.AdminPassword != "" {
		cfg.EnvVars["GF_SECURITY_ADMIN_PASSWORD"] = opts.AdminPassword
	}

	return cfg, nil
}

// DockerArgs returns the -e and -v arguments for docker run.
func (c *GrafanaConfig) DockerArgs() []string {
	var args []string
	for k, v := range c.EnvVars {
		args = append(args, "-e", k+"="+v)
	}
	for _, vm := range c.VolumeMounts {
		mount := vm.Source + ":" + vm.Target
		if vm.ReadOnly {
			mount += ":ro"
		}
		args = append(args, "-v", mount)
	}
	return args
}
