package grafana

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

var testMainTemplate = []byte(`apiVersion: 1
datasources:
- name: prometheus
  type: prometheus
  url: http://DB_ADDRESS
  access: proxy
  basicAuth: false
  isDefault: true
  jsonData:
    timeInterval: '20s'
- name: alertmanager
  type: alertmanager
  url: http://AM_ADDRESS
`)

var testLokiTemplate = []byte(`apiVersion: 1
datasources:
- name: loki
  type: loki
  url: http://LOKI_ADDRESS
`)

var testScyllaTemplate = []byte(`apiVersion: 1
datasources:
- name: scylla-datasource
  type: scylladb-scylla-datasource
`)

var testScyllaPasswordTemplate = []byte(`apiVersion: 1
datasources:
- name: scylla-datasource
  secureJsonData:
    user: 'SCYLLA_USER'
    password: 'SCYLLA_PSSWD'
`)

func testTemplates() DatasourceTemplates {
	return DatasourceTemplates{
		Main:           testMainTemplate,
		Loki:           testLokiTemplate,
		Scylla:         testScyllaTemplate,
		ScyllaPassword: testScyllaPasswordTemplate,
	}
}

func TestWriteDatasourceFiles_Basic(t *testing.T) {
	dir := t.TempDir()
	opts := DatasourceOptions{
		PrometheusAddress:   "aprom:9090",
		AlertManagerAddress: "aalert:9093",
		OutputBaseDir:       dir,
	}
	if err := WriteDatasourceFiles(testTemplates(), opts); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	outDir := filepath.Join(dir, "provisioning/datasources")

	// Check main datasource
	data, err := os.ReadFile(filepath.Join(outDir, "datasource.yaml"))
	if err != nil {
		t.Fatalf("reading datasource.yaml: %v", err)
	}
	content := string(data)
	if !strings.Contains(content, "http://aprom:9090") {
		t.Error("expected prometheus address in datasource.yaml")
	}
	if !strings.Contains(content, "http://aalert:9093") {
		t.Error("expected alertmanager address in datasource.yaml")
	}

	// Loki should not exist (no address given)
	if _, err := os.Stat(filepath.Join(outDir, "datasource.loki.yaml")); !os.IsNotExist(err) {
		t.Error("expected datasource.loki.yaml to not exist when no Loki address given")
	}

	// ScyllaDB datasource should exist (no credentials)
	data, err = os.ReadFile(filepath.Join(outDir, "datasource.scylla.yml"))
	if err != nil {
		t.Fatalf("reading datasource.scylla.yml: %v", err)
	}
	if !strings.Contains(string(data), "scylladb-scylla-datasource") {
		t.Error("expected scylla datasource type")
	}
}

func TestWriteDatasourceFiles_WithLoki(t *testing.T) {
	dir := t.TempDir()
	opts := DatasourceOptions{
		PrometheusAddress:   "aprom:9090",
		AlertManagerAddress: "aalert:9093",
		LokiAddress:         "loki:3100",
		OutputBaseDir:       dir,
	}
	if err := WriteDatasourceFiles(testTemplates(), opts); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	outDir := filepath.Join(dir, "provisioning/datasources")
	data, err := os.ReadFile(filepath.Join(outDir, "datasource.loki.yaml"))
	if err != nil {
		t.Fatalf("reading datasource.loki.yaml: %v", err)
	}
	if !strings.Contains(string(data), "http://loki:3100") {
		t.Error("expected loki address in datasource.loki.yaml")
	}
}

func TestWriteDatasourceFiles_WithScyllaCredentials(t *testing.T) {
	dir := t.TempDir()
	opts := DatasourceOptions{
		PrometheusAddress:   "aprom:9090",
		AlertManagerAddress: "aalert:9093",
		ScyllaUser:          "myuser",
		ScyllaPassword:      "mypass",
		OutputBaseDir:       dir,
	}
	if err := WriteDatasourceFiles(testTemplates(), opts); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	outDir := filepath.Join(dir, "provisioning/datasources")
	data, err := os.ReadFile(filepath.Join(outDir, "datasource.scylla.yml"))
	if err != nil {
		t.Fatalf("reading datasource.scylla.yml: %v", err)
	}
	content := string(data)
	if !strings.Contains(content, "myuser") {
		t.Error("expected scylla user in datasource")
	}
	if !strings.Contains(content, "mypass") {
		t.Error("expected scylla password in datasource")
	}
}

func TestWriteDatasourceFiles_CustomScrapeInterval(t *testing.T) {
	dir := t.TempDir()
	opts := DatasourceOptions{
		PrometheusAddress:   "aprom:9090",
		AlertManagerAddress: "aalert:9093",
		ScrapeInterval:      "30",
		OutputBaseDir:       dir,
	}
	if err := WriteDatasourceFiles(testTemplates(), opts); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	outDir := filepath.Join(dir, "provisioning/datasources")
	data, err := os.ReadFile(filepath.Join(outDir, "datasource.yaml"))
	if err != nil {
		t.Fatalf("reading datasource.yaml: %v", err)
	}
	if !strings.Contains(string(data), "timeInterval: '30s'") {
		t.Error("expected timeInterval: '30s' in datasource.yaml")
	}
}

func TestWriteDatasourceFiles_StackID(t *testing.T) {
	dir := t.TempDir()
	opts := DatasourceOptions{
		PrometheusAddress:   "aprom:9090",
		AlertManagerAddress: "aalert:9093",
		StackID:             2,
		OutputBaseDir:       dir,
	}
	if err := WriteDatasourceFiles(testTemplates(), opts); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	outDir := filepath.Join(dir, "stack/2/provisioning/datasources")
	if _, err := os.Stat(filepath.Join(outDir, "datasource.yaml")); err != nil {
		t.Errorf("expected datasource.yaml at stack path: %v", err)
	}
}
