// model.go — Bubbletea Model struct and Init().
//
// Responsibility: Define the application state (Model) and its initialization.
// The Model holds all UI state: which pane is active, window dimensions,
// and the sub-model components for each pane. In the Elm Architecture, the
// Model is the single source of truth — all rendering and updates derive from it.
package main

import (
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

// Model holds all application state for the bubbletea program.
// Every field here is rendered by View() and modified by Update().
type Model struct {
	// configPath is the path to projects.yml
	configPath string

	// activePane tracks which column is currently focused (receives key events)
	activePane int

	// windowWidth and windowHeight store the terminal dimensions,
	// updated whenever the terminal is resized (tea.WindowSizeMsg)
	windowWidth  int
	windowHeight int

	// quitting signals that the user wants to exit
	quitting bool

	// showProjects toggles the project switcher overlay
	showProjects bool

	// Sub-model components — each manages its own state and rendering
	issues   components.IssuesModel
	agents   components.AgentsModel
	events   components.EventsModel
	projects components.ProjectsModel
}

// NewModel creates a Model with sensible defaults and placeholder data.
func NewModel(configPath string) Model {
	m := Model{
		configPath:   configPath,
		activePane:   PaneIssues,
		issues:       components.NewIssuesModel(),
		agents:       components.NewAgentsModel(),
		events:       components.NewEventsModel(),
		projects:     components.NewProjectsModel(),
	}

	// Load placeholder data for demo purposes.
	// Layers 4+ will replace this with real data from Linear API and log parser.
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

// Init returns an initial command. For now, we just wait for the first
// WindowSizeMsg which bubbletea sends automatically on startup.
func (m Model) Init() tea.Cmd {
	return nil
}
