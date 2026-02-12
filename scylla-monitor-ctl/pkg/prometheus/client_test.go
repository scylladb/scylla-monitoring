package prometheus

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestPrometheusClient_Health(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/-/ready" {
			w.WriteHeader(200)
			return
		}
		w.WriteHeader(404)
	}))
	defer srv.Close()

	c := NewClient(srv.URL)
	if err := c.Health(); err != nil {
		t.Fatalf("health check failed: %v", err)
	}
}

func TestPrometheusClient_HealthFail(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(503)
	}))
	defer srv.Close()

	c := NewClient(srv.URL)
	if err := c.Health(); err == nil {
		t.Error("expected health check to fail")
	}
}

func TestPrometheusClient_Reload(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/-/reload" && r.Method == "POST" {
			w.WriteHeader(200)
			return
		}
		w.WriteHeader(404)
	}))
	defer srv.Close()

	c := NewClient(srv.URL)
	if err := c.Reload(); err != nil {
		t.Fatalf("reload failed: %v", err)
	}
}

func TestPrometheusClient_ReloadFail(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(403)
		w.Write([]byte("lifecycle API not enabled"))
	}))
	defer srv.Close()

	c := NewClient(srv.URL)
	if err := c.Reload(); err == nil {
		t.Error("expected reload to fail")
	}
}

func TestPrometheusClient_CreateSnapshot(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/api/v1/admin/tsdb/snapshot" && r.Method == "POST" {
			w.WriteHeader(200)
			w.Write([]byte(`{"status":"success","data":{"name":"20240101T000000Z-abc123"}}`))
			return
		}
		w.WriteHeader(404)
	}))
	defer srv.Close()

	c := NewClient(srv.URL)
	name, err := c.CreateSnapshot()
	if err != nil {
		t.Fatalf("snapshot failed: %v", err)
	}
	if name != "20240101T000000Z-abc123" {
		t.Errorf("expected snapshot name, got %s", name)
	}
}
