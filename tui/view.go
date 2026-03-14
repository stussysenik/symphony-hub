// view.go — Bubbletea View() function.
//
// Responsibility: Render the entire UI as a string. In the Elm Architecture,
// View is a pure function of the Model — it reads state but never modifies it.
// Bubbletea calls View() after every Update() and diffs the output to minimize
// terminal redraws.
package main

import (
	"fmt"

	"github.com/charmbracelet/lipgloss"
)

// View renders the entire TUI. Called by bubbletea after every Update().
func (m Model) View() string {
	if m.quitting {
		return "Goodbye!\n"
	}

	// Need minimum dimensions to render
	if m.windowWidth < 20 || m.windowHeight < 10 {
		return "Terminal too small. Please resize.\n"
	}

	// Layout calculations
	availableHeight := m.windowHeight - 4
	paneWidth := (m.windowWidth - 6) / 3
	if paneWidth < 15 {
		paneWidth = 15
	}

	// Build the three panes using component views
	issuesPane := m.renderPane("Issues [1]", PaneIssues, paneWidth, availableHeight, m.issues.View())
	agentsPane := m.renderPane("Agents [2]", PaneAgents, paneWidth, availableHeight, m.agents.View())
	eventsPane := m.renderPane("Events [3]", PaneEvents, paneWidth, availableHeight, m.events.View())

	// Join panes horizontally
	panes := lipgloss.JoinHorizontal(lipgloss.Top, issuesPane, " ", agentsPane, " ", eventsPane)

	// Title bar
	activeProject := "none"
	if p := m.projects.ActiveProject(); p != nil {
		activeProject = p.Name
	}
	title := m.theme.Title.Render(fmt.Sprintf("Symphony Hub — %s", activeProject))

	// Status bar with refresh info
	paneNames := []string{"Issues", "Agents", "Events"}
	statusText := fmt.Sprintf(
		" Active: %s | r: refresh | ?: help | Tab: switch | p: projects | q: quit",
		paneNames[m.activePane],
	)
	if m.statusMessage != "" {
		statusText += " | " + m.statusMessage
	}
	status := m.theme.StatusBar.Render(statusText)

	// Stack vertically: title, panes, status
	view := lipgloss.JoinVertical(lipgloss.Left, title, panes, status)

	// Help overlay takes priority
	if m.showHelp {
		overlay := m.theme.HelpOverlay.
			Width(50).
			Render(renderHelp())
		view = lipgloss.Place(
			m.windowWidth, m.windowHeight,
			lipgloss.Center, lipgloss.Center,
			overlay,
			lipgloss.WithWhitespaceChars(" "),
		)
	} else if m.showProjects {
		// Project switcher overlay
		overlay := m.theme.ProjectOverlay.
			Width(30).
			Render(m.projects.View())
		view = lipgloss.Place(
			m.windowWidth, m.windowHeight,
			lipgloss.Center, lipgloss.Center,
			overlay,
			lipgloss.WithWhitespaceChars(" "),
		)
	}

	return view
}

// renderPane wraps content in a bordered box with a header.
// The active pane gets a highlighted border from the theme.
func (m Model) renderPane(title string, paneIndex int, width int, height int, content string) string {
	style := m.theme.InactiveBorder
	if paneIndex == m.activePane {
		style = m.theme.ActiveBorder
	}

	header := m.theme.PaneHeader.Render(title)
	body := header + "\n" + content

	return style.
		Width(width).
		Height(height).
		Render(body)
}
