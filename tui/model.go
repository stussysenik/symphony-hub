// model.go — Bubbletea Model struct and Init().
//
// Responsibility: Define the application state (Model) and its initialization.
// The Model holds all UI state: which pane is active, window dimensions,
// and the data displayed in each pane. In the Elm Architecture, the Model is
// the single source of truth — all rendering and updates derive from it.
package main

import (
	tea "github.com/charmbracelet/bubbletea"
)

// Pane identifiers — used to track which pane is focused.
// The TUI has a 3-column layout: Issues | Agents | Events.
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

	// issueRows holds placeholder data for the issues pane
	issueRows [][]string

	// agentRows holds placeholder data for the agents pane
	agentRows [][]string

	// eventLines holds placeholder data for the events pane
	eventLines []string
}

// NewModel creates a Model with sensible defaults.
func NewModel(configPath string) Model {
	return Model{
		configPath: configPath,
		activePane: PaneIssues,
		issueRows: [][]string{
			{"CRE-42", "Add dark mode toggle", "In Progress", "2m ago"},
			{"CRE-41", "Fix nav layout", "Human Review", "15m ago"},
			{"CRE-40", "Update footer links", "Done", "1h ago"},
		},
		agentRows: [][]string{
			{"agent-1", "Working", "CRE-42", "2m 15s"},
			{"agent-2", "Idle", "—", "—"},
		},
		eventLines: []string{
			"[10:00:15] Agent started on CRE-42",
			"[10:00:18] Workspace created: v0-ipod/CRE-42",
			"[10:00:20] State change: Todo → In Progress",
			"[10:00:25] Plan posted to Linear workpad",
			"[10:02:00] File created: src/components/DarkModeToggle.tsx",
			"[10:04:12] Tests passing (3/3)",
		},
	}
}

// Init returns an initial command. For now, we just wait for the first
// WindowSizeMsg which bubbletea sends automatically on startup.
func (m Model) Init() tea.Cmd {
	return nil
}
