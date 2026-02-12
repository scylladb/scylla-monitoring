package grafana

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"
)

// Client is an HTTP client for the Grafana API.
type Client struct {
	BaseURL  string
	Username string
	Password string
	HTTP     *http.Client
}

// NewClient creates a new Grafana API client.
func NewClient(baseURL, username, password string) *Client {
	return &Client{
		BaseURL:  baseURL,
		Username: username,
		Password: password,
		HTTP:     &http.Client{Timeout: 30 * time.Second},
	}
}

func (c *Client) doRequest(method, path string, body interface{}) ([]byte, int, error) {
	var reqBody io.Reader
	if body != nil {
		data, err := json.Marshal(body)
		if err != nil {
			return nil, 0, fmt.Errorf("marshaling request body: %w", err)
		}
		reqBody = bytes.NewReader(data)
	}

	req, err := http.NewRequest(method, c.BaseURL+path, reqBody)
	if err != nil {
		return nil, 0, fmt.Errorf("creating request: %w", err)
	}

	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Accept", "application/json")
	if c.Username != "" {
		req.SetBasicAuth(c.Username, c.Password)
	}

	resp, err := c.HTTP.Do(req)
	if err != nil {
		return nil, 0, fmt.Errorf("executing request: %w", err)
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, resp.StatusCode, fmt.Errorf("reading response: %w", err)
	}

	return respBody, resp.StatusCode, nil
}

// Health checks the Grafana health endpoint.
func (c *Client) Health() error {
	_, code, err := c.doRequest("GET", "/api/health", nil)
	if err != nil {
		return err
	}
	if code != 200 {
		return fmt.Errorf("health check returned status %d", code)
	}
	return nil
}

// GetOrg returns the current org info.
func (c *Client) GetOrg() (map[string]interface{}, error) {
	data, code, err := c.doRequest("GET", "/api/org", nil)
	if err != nil {
		return nil, err
	}
	if code != 200 {
		return nil, fmt.Errorf("get org returned status %d: %s", code, data)
	}
	var result map[string]interface{}
	if err := json.Unmarshal(data, &result); err != nil {
		return nil, fmt.Errorf("parsing org response: %w", err)
	}
	return result, nil
}

// --- Datasource operations ---

// APIDatasource represents a Grafana datasource from the API.
type APIDatasource struct {
	ID        int                    `json:"id,omitempty"`
	UID       string                 `json:"uid,omitempty"`
	Name      string                 `json:"name"`
	Type      string                 `json:"type"`
	URL       string                 `json:"url"`
	Access    string                 `json:"access"`
	IsDefault bool                   `json:"isDefault"`
	BasicAuth bool                   `json:"basicAuth"`
	JSONData  map[string]interface{} `json:"jsonData,omitempty"`
}

// ListDatasources lists all datasources.
func (c *Client) ListDatasources() ([]APIDatasource, error) {
	data, code, err := c.doRequest("GET", "/api/datasources", nil)
	if err != nil {
		return nil, err
	}
	if code != 200 {
		return nil, fmt.Errorf("list datasources returned status %d: %s", code, data)
	}
	var result []APIDatasource
	if err := json.Unmarshal(data, &result); err != nil {
		return nil, fmt.Errorf("parsing datasources: %w", err)
	}
	return result, nil
}

// CreateDatasource creates a new datasource.
func (c *Client) CreateDatasource(ds APIDatasource) error {
	data, code, err := c.doRequest("POST", "/api/datasources", ds)
	if err != nil {
		return err
	}
	if code != 200 && code != 409 {
		return fmt.Errorf("create datasource returned status %d: %s", code, data)
	}
	return nil
}

// UpdateDatasource updates an existing datasource by ID.
func (c *Client) UpdateDatasource(id int, ds APIDatasource) error {
	data, code, err := c.doRequest("PUT", fmt.Sprintf("/api/datasources/%d", id), ds)
	if err != nil {
		return err
	}
	if code != 200 {
		return fmt.Errorf("update datasource returned status %d: %s", code, data)
	}
	return nil
}

// --- Dashboard operations ---

// DashboardUpload is the request body for uploading a dashboard.
type DashboardUpload struct {
	Dashboard json.RawMessage `json:"dashboard"`
	FolderID  int             `json:"folderId"`
	FolderUID string          `json:"folderUid,omitempty"`
	Overwrite bool            `json:"overwrite"`
}

// UploadDashboard uploads a dashboard JSON to Grafana.
func (c *Client) UploadDashboard(dashboardJSON []byte, folderID int, overwrite bool) error {
	payload := DashboardUpload{
		Dashboard: json.RawMessage(dashboardJSON),
		FolderID:  folderID,
		Overwrite: overwrite,
	}
	data, code, err := c.doRequest("POST", "/api/dashboards/db", payload)
	if err != nil {
		return err
	}
	if code != 200 {
		return fmt.Errorf("upload dashboard returned status %d: %s", code, data)
	}
	return nil
}

// DownloadDashboard downloads a dashboard by UID.
func (c *Client) DownloadDashboard(uid string) (json.RawMessage, error) {
	data, code, err := c.doRequest("GET", "/api/dashboards/uid/"+uid, nil)
	if err != nil {
		return nil, err
	}
	if code != 200 {
		return nil, fmt.Errorf("download dashboard returned status %d: %s", code, data)
	}
	return json.RawMessage(data), nil
}

// DashboardSearchResult represents a search result item.
type DashboardSearchResult struct {
	ID        int    `json:"id"`
	UID       string `json:"uid"`
	Title     string `json:"title"`
	URI       string `json:"uri"`
	Type      string `json:"type"`
	FolderID  int    `json:"folderId"`
	FolderUID string `json:"folderUid"`
}

// SearchDashboards searches for dashboards.
func (c *Client) SearchDashboards() ([]DashboardSearchResult, error) {
	data, code, err := c.doRequest("GET", "/api/search?type=dash-db", nil)
	if err != nil {
		return nil, err
	}
	if code != 200 {
		return nil, fmt.Errorf("search dashboards returned status %d: %s", code, data)
	}
	var result []DashboardSearchResult
	if err := json.Unmarshal(data, &result); err != nil {
		return nil, fmt.Errorf("parsing search results: %w", err)
	}
	return result, nil
}

// --- Folder operations ---

// Folder represents a Grafana folder.
type Folder struct {
	ID    int    `json:"id,omitempty"`
	UID   string `json:"uid,omitempty"`
	Title string `json:"title"`
}

// ListFolders returns all folders.
func (c *Client) ListFolders() ([]Folder, error) {
	data, code, err := c.doRequest("GET", "/api/folders", nil)
	if err != nil {
		return nil, err
	}
	if code != 200 {
		return nil, fmt.Errorf("list folders returned status %d: %s", code, data)
	}
	var result []Folder
	if err := json.Unmarshal(data, &result); err != nil {
		return nil, fmt.Errorf("parsing folders: %w", err)
	}
	return result, nil
}

// CreateFolder creates a new folder.
func (c *Client) CreateFolder(title, uid string) (*Folder, error) {
	payload := map[string]string{"title": title}
	if uid != "" {
		payload["uid"] = uid
	}
	data, code, err := c.doRequest("POST", "/api/folders", payload)
	if err != nil {
		return nil, err
	}
	if code != 200 && code != 409 {
		return nil, fmt.Errorf("create folder returned status %d: %s", code, data)
	}
	var result Folder
	if err := json.Unmarshal(data, &result); err != nil {
		return nil, fmt.Errorf("parsing folder: %w", err)
	}
	return &result, nil
}

// SetFolderPermissions sets permissions on a folder.
func (c *Client) SetFolderPermissions(uid string, permissions interface{}) error {
	data, code, err := c.doRequest("POST", fmt.Sprintf("/api/folders/%s/permissions", uid), permissions)
	if err != nil {
		return err
	}
	if code != 200 {
		return fmt.Errorf("set folder permissions returned status %d: %s", code, data)
	}
	return nil
}
