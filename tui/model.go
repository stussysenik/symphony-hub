// model.go — Bubbletea Model struct and Init().
//
// Responsibility: Define the application state (Model) and its initialization.
// The Model holds all UI state: which pane is active, window dimensions,
// and the sub-model components for each pane. In the Elm Architecture, the
// Model is the single source of truth — all rendering and updates derive from it.
package main

import (
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"symphony-hub/tui/components"
)

// Pane identifiers — used to track which pane is focused.
// The TUI has a 3-column layout: Issues | Agents | Events.
// Projects pane is toggled via 'p' key as an overlay.
const (
	PaneIssues  = 0
	PaneAgents  = 1
	PaneEvents  = 2
	PaneCount   = 3
)

// Refresh intervals for data sources.
// Linear is rate-limited so we poll less frequently.
// Logs are local files so we can poll faster.
const (
	linearRefreshInterval = 5 * time.Second
	logsRefreshInterval   = 2 * time.Second
)

// TickMsg is sent by the ticker to trigger data refresh.
type TickMsg struct {
	source string // "linear" or "logs"
}

// DataRefreshMsg carries refreshed data back to the model.
type DataRefreshMsg struct {
	issues []components.Issue
	events []components.Event
	err    error
}

// Model holds all application state for the bubbletea program.
type Model struct {
	// configPath is the path to projects.yml
	configPath string

	// logsRoot is the directory containing Symphony log files
	logsRoot string

	// linearAPIKey is the Linear API authentication key
	linearAPIKey string

	// activePane tracks which column is currently focused
	activePane int

	// windowWidth and windowHeight store the terminal dimensions
	windowWidth  int
	windowHeight int

	// quitting signals that the user wants to exit
	quitting bool

	// showProjects toggles the project switcher overlay
	showProjects bool

	// lastRefresh tracks when data was last fetched
	lastRefresh time.Time

	// statusMessage shows connection status or errors
	statusMessage string

	// Sub-model components — each manages its own state and rendering
	issues   components.IssuesModel
	agents   components.AgentsModel
	events   components.EventsModel
	projects components.ProjectsModel
}

// NewModel creates a Model with sensible defaults and placeholder data.
func NewModel(configPath string) Model {
	m := Model{
		configPath:    configPath,
		activePane:    PaneIssues,
		statusMessage: "Starting...",
		issues:        components.NewIssuesModel(),
		agents:        components.NewAgentsModel(),
		events:        components.NewEventsModel(),
		projects:      components.NewProjectsModel(),
	}

	// Load placeholder data for demo purposes.
	// When Linear API key is set, real data replaces this on first tick.
	m.issues.SetIssues([]components.Issue{
		{ID: "CRE-42", Title: "Add dark mode toggle", State: "In Progress", Updated: "2m ago"},
		{ID: "CRE-41", Title: "Fix nav layout", State: "Human Review", Updated: "15m ago"},
		{ID: "CRE-40", Title: "Update footer links", State: "Done", Updated: "1h ago"},
	})

	m.agents.SetAgents([]components.Agent{
		{Name: "agent-1", Status: "Working", Issue: "CRE-42", Duration: "2m 15s"},
		{Name: "agent-2", Status: "Idle", Issue: "—", Duration: "—"},
	})

	m.events.SetEvents([]components.Event{
		{Timestamp: "[10:00:15]", Type: "info", Message: "Agent started on CRE-42"},
		{Timestamp: "[10:00:18]", Type: "file_change", Message: "Workspace created: v0-ipod/CRE-42"},
		{Timestamp: "[10:00:20]", Type: "state_change", Message: "State: Todo → In Progress"},
		{Timestamp: "[10:00:25]", Type: "info", Message: "Plan posted to Linear workpad"},
		{Timestamp: "[10:02:00]", Type: "file_change", Message: "Created: src/components/DarkModeToggle.tsx"},
		{Timestamp: "[10:04:12]", Type: "success", Message: "Tests passing (3/3)"},
	})

	m.projects.SetProjects([]components.Project{
		{Name: "v0-ipod", GitHubURL: "https://github.com/stussysenik/v0-ipod.git", LinearProjectSlug: "dabd6fee0112", MaxAgents: 2},
		{Name: "mymind-clone-web", GitHubURL: "https://github.com/stussysenik/mymind-clone-web.git", LinearProjectSlug: "372637c999d1", MaxAgents: 2},
		{Name: "recap", GitHubURL: "https://github.com/stussysenik/recap.git", LinearProjectSlug: "15ec4aaf8ef1", MaxAgents: 2},
	})

	return m
}

// Init returns initial commands — starts the data refresh tickers.
// In bubbletea, Cmd functions run asynchronously and send messages
// back to Update() when they complete.
func (m Model) Init() tea.Cmd {
	return tea.Batch(
		tickLinear(),
		tickLogs(),
	)
}

// tickLinear creates a timer that fires a TickMsg for Linear refresh.
func tickLinear() tea.Cmd {
	return tea.Tick(linearRefreshInterval, func(t time.Time) tea.Msg {
		return TickMsg{source: "linear"}
	})
}

// tickLogs creates a timer that fires a TickMsg for log refresh.
func tickLogs() tea.Cmd {
	return tea.Tick(logsRefreshInterval, func(t time.Time) tea.Msg {
		return TickMsg{source: "logs"}
	})
}
