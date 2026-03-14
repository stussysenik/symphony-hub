// client.go — Linear GraphQL API client for the TUI.
//
// Responsibility: Fetch issues from Linear's GraphQL API for a given project.
// This is a lightweight Go client that mirrors the queries in Symphony's
// Elixir client (linear/client.ex) but only fetches the fields needed for
// the TUI display.
//
// Architecture note: The TUI doesn't go through Symphony's Elixir process —
// it queries Linear directly. This means the TUI works even when Symphony
// isn't running, which is useful for reviewing issue status.
package linear

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"
)

const linearAPIURL = "https://api.linear.app/graphql"

// Client wraps HTTP calls to the Linear GraphQL API.
type Client struct {
	apiKey     string
	httpClient *http.Client
}

// NewClient creates a Linear API client with the given API key.
func NewClient(apiKey string) *Client {
	return &Client{
		apiKey: apiKey,
		httpClient: &http.Client{
			Timeout: 10 * time.Second,
		},
	}
}

// Issue represents a Linear issue with fields needed for TUI display.
type Issue struct {
	ID         string    `json:"id"`
	Identifier string    `json:"identifier"`
	Title      string    `json:"title"`
	State      string    `json:"-"` // Extracted from nested state object
	UpdatedAt  time.Time `json:"updatedAt"`
	URL        string    `json:"url"`
}

// graphqlRequest is the JSON body sent to Linear's GraphQL endpoint.
type graphqlRequest struct {
	Query     string                 `json:"query"`
	Variables map[string]interface{} `json:"variables"`
}

// graphqlResponse is the top-level JSON response from Linear.
type graphqlResponse struct {
	Data struct {
		Project struct {
			Issues struct {
				Nodes []issueNode `json:"nodes"`
			} `json:"issues"`
		} `json:"project"`
	} `json:"data"`
	Errors []struct {
		Message string `json:"message"`
	} `json:"errors"`
}

// issueNode mirrors the nested JSON structure of a Linear issue.
type issueNode struct {
	ID         string `json:"id"`
	Identifier string `json:"identifier"`
	Title      string `json:"title"`
	State      struct {
		Name string `json:"name"`
	} `json:"state"`
	UpdatedAt string `json:"updatedAt"`
	URL       string `json:"url"`
}

// The GraphQL query fetches issues for a project by its slug ID.
// This matches the fields Symphony's Elixir client fetches, filtered
// to only what the TUI needs for display.
const issuesQuery = `
query($projectId: String!, $first: Int) {
  project(id: $projectId) {
    issues(
      first: $first
      orderBy: updatedAt
      filter: { state: { type: { nin: ["completed", "cancelled"] } } }
    ) {
      nodes {
        id
        identifier
        title
        state { name }
        updatedAt
        url
      }
    }
  }
}
`

// FetchIssues retrieves open issues for a project from Linear.
// projectSlug is the Linear project ID (e.g., "dabd6fee0112").
func (c *Client) FetchIssues(projectSlug string) ([]Issue, error) {
	reqBody := graphqlRequest{
		Query: issuesQuery,
		Variables: map[string]interface{}{
			"projectId": projectSlug,
			"first":     50,
		},
	}

	bodyBytes, err := json.Marshal(reqBody)
	if err != nil {
		return nil, fmt.Errorf("marshal request: %w", err)
	}

	req, err := http.NewRequest("POST", linearAPIURL, bytes.NewReader(bodyBytes))
	if err != nil {
		return nil, fmt.Errorf("create request: %w", err)
	}

	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", c.apiKey)

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("linear API request: %w", err)
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("read response: %w", err)
	}

	if resp.StatusCode != 200 {
		return nil, fmt.Errorf("linear API returned %d: %s", resp.StatusCode, string(respBody))
	}

	var gqlResp graphqlResponse
	if err := json.Unmarshal(respBody, &gqlResp); err != nil {
		return nil, fmt.Errorf("parse response: %w", err)
	}

	if len(gqlResp.Errors) > 0 {
		return nil, fmt.Errorf("linear GraphQL error: %s", gqlResp.Errors[0].Message)
	}

	// Convert API nodes to our Issue type
	issues := make([]Issue, 0, len(gqlResp.Data.Project.Issues.Nodes))
	for _, node := range gqlResp.Data.Project.Issues.Nodes {
		updatedAt, _ := time.Parse(time.RFC3339, node.UpdatedAt)
		issues = append(issues, Issue{
			ID:         node.ID,
			Identifier: node.Identifier,
			Title:      node.Title,
			State:      node.State.Name,
			UpdatedAt:  updatedAt,
			URL:        node.URL,
		})
	}

	return issues, nil
}

// FormatTimeSince returns a human-readable relative time string.
// Used by the TUI to show "2m ago", "1h ago", etc.
func FormatTimeSince(t time.Time) string {
	d := time.Since(t)
	switch {
	case d < time.Minute:
		return "just now"
	case d < time.Hour:
		return fmt.Sprintf("%dm ago", int(d.Minutes()))
	case d < 24*time.Hour:
		return fmt.Sprintf("%dh ago", int(d.Hours()))
	default:
		return fmt.Sprintf("%dd ago", int(d.Hours()/24))
	}
}
