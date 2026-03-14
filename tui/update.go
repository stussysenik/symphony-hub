// update.go — Bubbletea Update() function.
//
// Responsibility: Handle all messages (key presses, window resizes, ticks)
// and return the updated Model + any follow-up commands. In the Elm
// Architecture, Update is the ONLY place where state changes happen.
// This makes state transitions predictable and easy to debug.
package main

import (
	tea "github.com/charmbracelet/bubbletea"
	"symphony-hub/tui/components"
)

// Update processes incoming messages and returns the updated model.
// Every key press, window resize, and timer tick flows through here.
func (m Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	var cmd tea.Cmd

	switch msg := msg.(type) {

	// Window resize — bubbletea sends this on startup and whenever
	// the terminal dimensions change.
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

	// Project switch — triggered when user selects a project
	case components.ProjectSwitchedMsg:
		m.showProjects = false
		// Future: trigger data refresh for new project
		return m, nil

	// Key press — all keyboard input is handled here.
	case tea.KeyMsg:
		// Global keys (always active regardless of pane focus)
		switch msg.String() {
		case "q", "ctrl+c":
			m.quitting = true
			return m, tea.Quit

		// Toggle project switcher overlay
		case "p":
			m.showProjects = !m.showProjects
			if m.showProjects {
				m.projects.SetFocused(true)
			} else {
				m.projects.SetFocused(false)
				m.updateFocus()
			}
			return m, nil

		// Escape closes overlays
		case "esc":
			if m.showProjects {
				m.showProjects = false
				m.projects.SetFocused(false)
				m.updateFocus()
				return m, nil
			}

		// Tab / shift+tab: cycle through panes
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

		// Number keys: jump directly to a pane
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

// updateFocus synchronizes the focused state of all sub-models
// with the currently active pane.
func (m *Model) updateFocus() {
	m.issues.SetFocused(m.activePane == PaneIssues)
	m.agents.SetFocused(m.activePane == PaneAgents)
	m.events.SetFocused(m.activePane == PaneEvents)
}
