package grafana

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestClient_Health(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/api/health" {
			w.WriteHeader(200)
			w.Write([]byte(`{"database":"ok"}`))
			return
		}
		w.WriteHeader(404)
	}))
	defer srv.Close()

	c := NewClient(srv.URL, "admin", "admin")
	if err := c.Health(); err != nil {
		t.Fatalf("health check failed: %v", err)
	}
}

func TestClient_GetOrg(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/api/org" {
			w.WriteHeader(200)
			w.Write([]byte(`{"id":1,"name":"Main Org."}`))
			return
		}
		w.WriteHeader(404)
	}))
	defer srv.Close()

	c := NewClient(srv.URL, "admin", "admin")
	org, err := c.GetOrg()
	if err != nil {
		t.Fatalf("get org failed: %v", err)
	}
	if org["name"] != "Main Org." {
		t.Errorf("expected org name 'Main Org.', got %v", org["name"])
	}
}

func TestClient_ListDatasources(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/api/datasources" && r.Method == "GET" {
			w.WriteHeader(200)
			w.Write([]byte(`[{"id":1,"name":"prometheus","type":"prometheus","url":"http://localhost:9090"}]`))
			return
		}
		w.WriteHeader(404)
	}))
	defer srv.Close()

	c := NewClient(srv.URL, "admin", "admin")
	ds, err := c.ListDatasources()
	if err != nil {
		t.Fatalf("list datasources failed: %v", err)
	}
	if len(ds) != 1 {
		t.Fatalf("expected 1 datasource, got %d", len(ds))
	}
	if ds[0].Name != "prometheus" {
		t.Errorf("expected datasource name 'prometheus', got %s", ds[0].Name)
	}
}

func TestClient_CreateDatasource(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/api/datasources" && r.Method == "POST" {
			w.WriteHeader(200)
			w.Write([]byte(`{"id":1,"message":"Datasource added"}`))
			return
		}
		w.WriteHeader(404)
	}))
	defer srv.Close()

	c := NewClient(srv.URL, "admin", "admin")
	err := c.CreateDatasource(APIDatasource{
		Name: "test",
		Type: "prometheus",
		URL:  "http://localhost:9090",
	})
	if err != nil {
		t.Fatalf("create datasource failed: %v", err)
	}
}

func TestClient_UploadDashboard(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/api/dashboards/db" && r.Method == "POST" {
			var payload DashboardUpload
			json.NewDecoder(r.Body).Decode(&payload)
			if !payload.Overwrite {
				t.Error("expected overwrite=true")
			}
			w.WriteHeader(200)
			w.Write([]byte(`{"id":1,"uid":"abc","status":"success"}`))
			return
		}
		w.WriteHeader(404)
	}))
	defer srv.Close()

	c := NewClient(srv.URL, "admin", "admin")
	dash := []byte(`{"title":"Test Dashboard"}`)
	if err := c.UploadDashboard(dash, 0, true); err != nil {
		t.Fatalf("upload dashboard failed: %v", err)
	}
}

func TestClient_DownloadDashboard(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/api/dashboards/uid/abc123" {
			w.WriteHeader(200)
			w.Write([]byte(`{"dashboard":{"title":"Test"},"meta":{}}`))
			return
		}
		w.WriteHeader(404)
	}))
	defer srv.Close()

	c := NewClient(srv.URL, "admin", "admin")
	data, err := c.DownloadDashboard("abc123")
	if err != nil {
		t.Fatalf("download dashboard failed: %v", err)
	}
	if len(data) == 0 {
		t.Error("expected non-empty dashboard data")
	}
}

func TestClient_SearchDashboards(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/api/search" {
			w.WriteHeader(200)
			w.Write([]byte(`[{"id":1,"uid":"abc","title":"Overview","type":"dash-db"}]`))
			return
		}
		w.WriteHeader(404)
	}))
	defer srv.Close()

	c := NewClient(srv.URL, "admin", "admin")
	results, err := c.SearchDashboards()
	if err != nil {
		t.Fatalf("search dashboards failed: %v", err)
	}
	if len(results) != 1 {
		t.Fatalf("expected 1 result, got %d", len(results))
	}
	if results[0].Title != "Overview" {
		t.Errorf("expected title 'Overview', got %s", results[0].Title)
	}
}

func TestClient_Folders(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch {
		case r.URL.Path == "/api/folders" && r.Method == "GET":
			w.WriteHeader(200)
			w.Write([]byte(`[{"id":1,"uid":"abc","title":"General"}]`))
		case r.URL.Path == "/api/folders" && r.Method == "POST":
			w.WriteHeader(200)
			w.Write([]byte(`{"id":2,"uid":"def","title":"New Folder"}`))
		default:
			w.WriteHeader(404)
		}
	}))
	defer srv.Close()

	c := NewClient(srv.URL, "admin", "admin")
	folders, err := c.ListFolders()
	if err != nil {
		t.Fatalf("list folders failed: %v", err)
	}
	if len(folders) != 1 {
		t.Fatalf("expected 1 folder, got %d", len(folders))
	}

	folder, err := c.CreateFolder("New Folder", "def")
	if err != nil {
		t.Fatalf("create folder failed: %v", err)
	}
	if folder.Title != "New Folder" {
		t.Errorf("expected title 'New Folder', got %s", folder.Title)
	}
}

func TestClient_BasicAuth(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		user, pass, ok := r.BasicAuth()
		if !ok || user != "admin" || pass != "secret" {
			w.WriteHeader(401)
			return
		}
		w.WriteHeader(200)
		w.Write([]byte(`{"database":"ok"}`))
	}))
	defer srv.Close()

	c := NewClient(srv.URL, "admin", "secret")
	if err := c.Health(); err != nil {
		t.Fatalf("auth should have worked: %v", err)
	}

	c2 := NewClient(srv.URL, "admin", "wrong")
	if err := c2.Health(); err == nil {
		t.Error("expected auth failure with wrong password")
	}
}
