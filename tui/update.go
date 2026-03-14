// update.go — Bubbletea Update() function.
//
// Responsibility: Handle all messages (key presses, window resizes, ticks,
// data refreshes) and return the updated Model + any follow-up commands.
// In the Elm Architecture, Update is the ONLY place where state changes happen.
package main

import (
	"fmt"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"symphony-hub/tui/components"
	"symphony-hub/tui/linear"
	"symphony-hub/tui/parser"
)

// Update processes incoming messages and returns the updated model.
func (m Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	var cmd tea.Cmd

	switch msg := msg.(type) {

	// Window resize
	case tea.WindowSizeMsg:
		m.windowWidth = msg.Width
		m.windowHeight = msg.Height
		paneWidth := (m.windowWidth - 6) / 3
		paneHeight := m.windowHeight - 4
		m.issues.SetSize(paneWidth, paneHeight)
		m.agents.SetSize(paneWidth, paneHeight)
		m.events.SetSize(paneWidth, paneHeight)
		m.projects.SetSize(paneWidth, paneHeight)
		return m, nil

	// Data refresh tick — triggers async data fetching
	case TickMsg:
		switch msg.source {
		case "linear":
			return m, tea.Batch(
				m.fetchLinearIssues(),
				tickLinear(), // Schedule next tick
			)
		case "logs":
			return m, tea.Batch(
				m.fetchLogEvents(),
				tickLogs(), // Schedule next tick
			)
		}
		return m, nil

	// Data arrived from async fetch
	case DataRefreshMsg:
		if msg.err != nil {
			m.statusMessage = fmt.Sprintf("Error: %v", msg.err)
		} else {
			m.lastRefresh = time.Now()
			m.statusMessage = fmt.Sprintf("Last refresh: %s", m.lastRefresh.Format("15:04:05"))

			if msg.issues != nil {
				m.issues.SetIssues(msg.issues)
				// Derive agent data from issues in "In Progress" state
				m.agents.SetAgents(deriveAgents(msg.issues))
			}
			if msg.events != nil {
				m.events.SetEvents(msg.events)
			}
		}
		return m, nil

	// Project switch
	case components.ProjectSwitchedMsg:
		m.showProjects = false
		m.statusMessage = fmt.Sprintf("Switched to %s", msg.Project.Name)
		// Trigger immediate refresh for new project
		return m, tea.Batch(
			m.fetchLinearIssues(),
			m.fetchLogEvents(),
		)

	// Key press
	case tea.KeyMsg:
		switch msg.String() {
		case "q", "ctrl+c":
			m.quitting = true
			return m, tea.Quit

		case "p":
			m.showProjects = !m.showProjects
			if m.showProjects {
				m.projects.SetFocused(true)
			} else {
				m.projects.SetFocused(false)
				m.updateFocus()
			}
			return m, nil

		case "esc":
			if m.showProjects {
				m.showProjects = false
				m.projects.SetFocused(false)
				m.updateFocus()
				return m, nil
			}

		// Manual refresh
		case "r":
			m.statusMessage = "Refreshing..."
			return m, tea.Batch(
				m.fetchLinearIssues(),
				m.fetchLogEvents(),
			)

		case "tab":
			if !m.showProjects {
				m.activePane = (m.activePane + 1) % PaneCount
				m.updateFocus()
				return m, nil
			}

		case "shift+tab":
			if !m.showProjects {
				m.activePane = (m.activePane - 1 + PaneCount) % PaneCount
				m.updateFocus()
				return m, nil
			}

		case "1":
			if !m.showProjects {
				m.activePane = PaneIssues
				m.updateFocus()
				return m, nil
			}
		case "2":
			if !m.showProjects {
				m.activePane = PaneAgents
				m.updateFocus()
				return m, nil
			}
		case "3":
			if !m.showProjects {
				m.activePane = PaneEvents
				m.updateFocus()
				return m, nil
			}
		}
	}

	// Delegate to the focused sub-model
	if m.showProjects {
		m.projects, cmd = m.projects.Update(msg)
		return m, cmd
	}

	switch m.activePane {
	case PaneIssues:
		m.issues, cmd = m.issues.Update(msg)
	case PaneAgents:
		m.agents, cmd = m.agents.Update(msg)
	case PaneEvents:
		m.events, cmd = m.events.Update(msg)
	}

	return m, cmd
}

// fetchLinearIssues creates an async command that fetches issues from Linear.
// The command runs in a goroutine and sends a DataRefreshMsg when done.
func (m Model) fetchLinearIssues() tea.Cmd {
	if m.linearAPIKey == "" {
		return nil // No API key, keep placeholder data
	}

	activeProject := m.projects.ActiveProject()
	if activeProject == nil {
		return nil
	}

	slug := activeProject.LinearProjectSlug

	return func() tea.Msg {
		client := linear.NewClient(m.linearAPIKey)
		apiIssues, err := client.FetchIssues(slug)
		if err != nil {
			return DataRefreshMsg{err: err}
		}

		// Convert Linear API issues to component issues
		issues := make([]components.Issue, len(apiIssues))
		for i, issue := range apiIssues {
			issues[i] = components.Issue{
				ID:      issue.Identifier,
				Title:   issue.Title,
				State:   issue.State,
				Updated: linear.FormatTimeSince(issue.UpdatedAt),
			}
		}

		return DataRefreshMsg{issues: issues}
	}
}

// fetchLogEvents creates an async command that parses log files.
func (m Model) fetchLogEvents() tea.Cmd {
	if m.logsRoot == "" {
		return nil // No logs root configured, keep placeholder data
	}

	activeProject := m.projects.ActiveProject()
	if activeProject == nil {
		return nil
	}

	projectName := activeProject.Name
	logsRoot := m.logsRoot

	return func() tea.Msg {
		p := parser.NewLogParser(logsRoot)
		logEvents, err := p.TailLogFile(projectName, 100)
		if err != nil {
			return DataRefreshMsg{err: err}
		}

		// Convert parser events to component events
		events := make([]components.Event, len(logEvents))
		for i, e := range logEvents {
			events[i] = components.Event{
				Timestamp: e.Timestamp,
				Type:      e.Type,
				Message:   e.Message,
			}
		}

		return DataRefreshMsg{events: events}
	}
}

// deriveAgents creates agent status entries from issue data.
// Issues in "In Progress" state imply an active agent.
func deriveAgents(issues []components.Issue) []components.Agent {
	var agents []components.Agent
	agentNum := 1

	for _, issue := range issues {
		if issue.State == "In Progress" {
			agents = append(agents, components.Agent{
				Name:     fmt.Sprintf("agent-%d", agentNum),
				Status:   "Working",
				Issue:    issue.ID,
				Duration: issue.Updated,
			})
			agentNum++
		}
	}

	// If no agents are working, show an idle slot
	if len(agents) == 0 {
		agents = append(agents, components.Agent{
			Name:     "agent-1",
			Status:   "Idle",
			Issue:    "—",
			Duration: "—",
		})
	}

	return agents
}

// updateFocus synchronizes the focused state of all sub-models.
func (m *Model) updateFocus() {
	m.issues.SetFocused(m.activePane == PaneIssues)
	m.agents.SetFocused(m.activePane == PaneAgents)
	m.events.SetFocused(m.activePane == PaneEvents)
}
