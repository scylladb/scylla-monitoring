package prometheus

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"
)

// Client is an HTTP client for the Prometheus API.
type Client struct {
	BaseURL string
	HTTP    *http.Client
}

// NewClient creates a new Prometheus API client.
func NewClient(baseURL string) *Client {
	return &Client{
		BaseURL: baseURL,
		HTTP:    &http.Client{Timeout: 30 * time.Second},
	}
}

// Health checks Prometheus readiness.
func (c *Client) Health() error {
	resp, err := c.HTTP.Get(c.BaseURL + "/-/ready")
	if err != nil {
		return fmt.Errorf("prometheus health check: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		return fmt.Errorf("prometheus not ready: status %d", resp.StatusCode)
	}
	return nil
}

// Reload triggers a hot-reload of the Prometheus configuration.
// Requires --web.enable-lifecycle flag on Prometheus.
func (c *Client) Reload() error {
	resp, err := c.HTTP.Post(c.BaseURL+"/-/reload", "", nil)
	if err != nil {
		return fmt.Errorf("prometheus reload: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		body, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("prometheus reload failed (status %d): %s", resp.StatusCode, body)
	}
	return nil
}

// SnapshotResponse is the response from the snapshot API.
type SnapshotResponse struct {
	Status string `json:"status"`
	Data   struct {
		Name string `json:"name"`
	} `json:"data"`
}

// CreateSnapshot creates a TSDB snapshot and returns the snapshot name.
// Requires --web.enable-admin-api flag on Prometheus.
func (c *Client) CreateSnapshot() (string, error) {
	resp, err := c.HTTP.Post(c.BaseURL+"/api/v1/admin/tsdb/snapshot", "", nil)
	if err != nil {
		return "", fmt.Errorf("creating snapshot: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", fmt.Errorf("reading snapshot response: %w", err)
	}

	if resp.StatusCode != 200 {
		return "", fmt.Errorf("snapshot failed (status %d): %s", resp.StatusCode, body)
	}

	var result SnapshotResponse
	if err := json.Unmarshal(body, &result); err != nil {
		return "", fmt.Errorf("parsing snapshot response: %w", err)
	}

	if result.Status != "success" {
		return "", fmt.Errorf("snapshot returned status: %s", result.Status)
	}

	return result.Data.Name, nil
}
