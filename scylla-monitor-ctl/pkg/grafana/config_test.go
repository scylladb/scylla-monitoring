package grafana

import (
	"os"
	"path/filepath"
	"testing"
)

func TestNewConfig_Defaults(t *testing.T) {
	cfg, err := NewConfig(GrafanaOptions{})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if cfg.EnvVars["GF_AUTH_BASIC_ENABLED"] != "false" {
		t.Errorf("expected basic auth disabled by default, got %s", cfg.EnvVars["GF_AUTH_BASIC_ENABLED"])
	}
	if cfg.EnvVars["GF_AUTH_ANONYMOUS_ENABLED"] != "false" {
		t.Errorf("expected anonymous disabled by default, got %s", cfg.EnvVars["GF_AUTH_ANONYMOUS_ENABLED"])
	}
	if cfg.EnvVars["GF_AUTH_ANONYMOUS_ORG_ROLE"] != "Admin" {
		t.Errorf("expected anonymous role Admin, got %s", cfg.EnvVars["GF_AUTH_ANONYMOUS_ORG_ROLE"])
	}
	if len(cfg.VolumeMounts) != 0 {
		t.Errorf("expected no volume mounts, got %d", len(cfg.VolumeMounts))
	}
}

func TestNewConfig_WithLDAP(t *testing.T) {
	// Create a temp LDAP config file
	tmpDir := t.TempDir()
	ldapFile := filepath.Join(tmpDir, "ldap.toml")
	if err := os.WriteFile(ldapFile, []byte("[[servers]]\nhost = \"ldap.example.com\"\n"), 0644); err != nil {
		t.Fatal(err)
	}

	cfg, err := NewConfig(GrafanaOptions{
		LDAPConfigFile: ldapFile,
		Anonymous:      true, // should be overridden to false by LDAP
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	// LDAP env vars
	if cfg.EnvVars["GF_AUTH_LDAP_ENABLED"] != "true" {
		t.Error("expected GF_AUTH_LDAP_ENABLED=true")
	}
	if cfg.EnvVars["GF_AUTH_LDAP_CONFIG_FILE"] != "/etc/grafana/ldap.toml" {
		t.Errorf("expected LDAP config path /etc/grafana/ldap.toml, got %s", cfg.EnvVars["GF_AUTH_LDAP_CONFIG_FILE"])
	}
	if cfg.EnvVars["GF_AUTH_LDAP_ALLOW_SIGN_UP"] != "true" {
		t.Error("expected GF_AUTH_LDAP_ALLOW_SIGN_UP=true")
	}

	// LDAP forces basic auth on, anonymous off
	if cfg.EnvVars["GF_AUTH_BASIC_ENABLED"] != "true" {
		t.Error("expected LDAP to force basic auth on")
	}
	if cfg.EnvVars["GF_AUTH_ANONYMOUS_ENABLED"] != "false" {
		t.Error("expected LDAP to force anonymous off")
	}

	// Volume mount
	if len(cfg.VolumeMounts) != 1 {
		t.Fatalf("expected 1 volume mount, got %d", len(cfg.VolumeMounts))
	}
	vm := cfg.VolumeMounts[0]
	if vm.Target != "/etc/grafana/ldap.toml" {
		t.Errorf("expected target /etc/grafana/ldap.toml, got %s", vm.Target)
	}
	if !vm.ReadOnly {
		t.Error("expected LDAP mount to be read-only")
	}
}

func TestNewConfig_LDAPFileNotFound(t *testing.T) {
	_, err := NewConfig(GrafanaOptions{
		LDAPConfigFile: "/nonexistent/ldap.toml",
	})
	if err == nil {
		t.Error("expected error for missing LDAP config file")
	}
}

func TestNewConfig_AdminPassword(t *testing.T) {
	cfg, err := NewConfig(GrafanaOptions{
		AdminPassword: "secret123",
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if cfg.EnvVars["GF_SECURITY_ADMIN_PASSWORD"] != "secret123" {
		t.Errorf("expected admin password secret123, got %s", cfg.EnvVars["GF_SECURITY_ADMIN_PASSWORD"])
	}
}

func TestNewConfig_DisableAnonymous(t *testing.T) {
	cfg, err := NewConfig(GrafanaOptions{
		Anonymous:        true,
		DisableAnonymous: true,
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if cfg.EnvVars["GF_AUTH_ANONYMOUS_ENABLED"] != "false" {
		t.Error("expected DisableAnonymous to override Anonymous=true")
	}
}

func TestNewConfig_CustomRole(t *testing.T) {
	cfg, err := NewConfig(GrafanaOptions{
		AnonymousRole: "Viewer",
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if cfg.EnvVars["GF_AUTH_ANONYMOUS_ORG_ROLE"] != "Viewer" {
		t.Errorf("expected role Viewer, got %s", cfg.EnvVars["GF_AUTH_ANONYMOUS_ORG_ROLE"])
	}
}

func TestDockerArgs(t *testing.T) {
	cfg := &GrafanaConfig{
		EnvVars: map[string]string{
			"GF_AUTH_LDAP_ENABLED": "true",
		},
		VolumeMounts: []VolumeMount{
			{Source: "/tmp/ldap.toml", Target: "/etc/grafana/ldap.toml", ReadOnly: true},
		},
	}
	args := cfg.DockerArgs()

	foundEnv := false
	foundVol := false
	for i, a := range args {
		if a == "-e" && i+1 < len(args) && args[i+1] == "GF_AUTH_LDAP_ENABLED=true" {
			foundEnv = true
		}
		if a == "-v" && i+1 < len(args) && args[i+1] == "/tmp/ldap.toml:/etc/grafana/ldap.toml:ro" {
			foundVol = true
		}
	}
	if !foundEnv {
		t.Error("expected -e GF_AUTH_LDAP_ENABLED=true in docker args")
	}
	if !foundVol {
		t.Error("expected -v /tmp/ldap.toml:/etc/grafana/ldap.toml:ro in docker args")
	}
}
