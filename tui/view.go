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

// Base styles — lipgloss uses a builder pattern for terminal styling.
// Each style is immutable; methods return new copies.
var (
	// Pane border styles
	activeBorderStyle = lipgloss.NewStyle().
		Border(lipgloss.RoundedBorder()).
		BorderForeground(lipgloss.Color("39")). // Bright blue
		Padding(0, 1)

	inactiveBorderStyle = lipgloss.NewStyle().
		Border(lipgloss.RoundedBorder()).
		BorderForeground(lipgloss.Color("240")). // Gray
		Padding(0, 1)

	// Header style for pane titles
	headerStyle = lipgloss.NewStyle().
		Bold(true).
		Foreground(lipgloss.Color("39"))

	// Status bar at the bottom
	statusBarStyle = lipgloss.NewStyle().
		Foreground(lipgloss.Color("240"))

	// Title bar at the top
	titleStyle = lipgloss.NewStyle().
		Bold(true).
		Foreground(lipgloss.Color("205")). // Pink
		Padding(0, 1)

	// Project overlay style
	projectOverlayStyle = lipgloss.NewStyle().
		Border(lipgloss.DoubleBorder()).
		BorderForeground(lipgloss.Color("205")).
		Padding(1, 2)
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
	title := titleStyle.Render(fmt.Sprintf("Symphony Hub — %s", activeProject))

	// Status bar
	paneNames := []string{"Issues", "Agents", "Events"}
	status := statusBarStyle.Render(fmt.Sprintf(
		" Active: %s | Tab: switch | 1-3: jump | p: projects | q: quit",
		paneNames[m.activePane],
	))

	// Stack vertically: title, panes, status
	view := lipgloss.JoinVertical(lipgloss.Left, title, panes, status)

	// Overlay project switcher if open
	if m.showProjects {
		overlay := projectOverlayStyle.
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
// The active pane gets a highlighted border.
func (m Model) renderPane(title string, paneIndex int, width int, height int, content string) string {
	style := inactiveBorderStyle
	if paneIndex == m.activePane {
		style = activeBorderStyle
	}

	header := headerStyle.Render(title)
	body := header + "\n" + content

	return style.
		Width(width).
		Height(height).
		Render(body)
}
