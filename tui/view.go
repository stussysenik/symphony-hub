// view.go — Bubbletea View() function.
//
// Responsibility: Render the entire UI as a string. In the Elm Architecture,
// View is a pure function of the Model — it reads state but never modifies it.
// Bubbletea calls View() after every Update() and diffs the output to minimize
// terminal redraws.
package main

import (
	"fmt"
	"strings"

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
	// Reserve 3 lines: 1 for title bar, 1 for status bar, 1 for padding
	availableHeight := m.windowHeight - 4
	// Divide width into 3 columns with gaps
	paneWidth := (m.windowWidth - 6) / 3 // -6 for borders and gaps
	if paneWidth < 15 {
		paneWidth = 15
	}

	// Build the three panes
	issuesPane := m.renderPane("Issues", PaneIssues, paneWidth, availableHeight, m.renderIssues())
	agentsPane := m.renderPane("Agents", PaneAgents, paneWidth, availableHeight, m.renderAgents())
	eventsPane := m.renderPane("Events", PaneEvents, paneWidth, availableHeight, m.renderEvents())

	// Join panes horizontally
	panes := lipgloss.JoinHorizontal(lipgloss.Top, issuesPane, " ", agentsPane, " ", eventsPane)

	// Title bar
	title := titleStyle.Render("Symphony Hub")

	// Status bar
	paneNames := []string{"Issues", "Agents", "Events"}
	status := statusBarStyle.Render(fmt.Sprintf(
		" Active: %s | Tab: switch pane | 1-3: jump | q: quit",
		paneNames[m.activePane],
	))

	// Stack vertically: title, panes, status
	return lipgloss.JoinVertical(lipgloss.Left, title, panes, status)
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

// renderIssues formats the issues table as a simple aligned text block.
func (m Model) renderIssues() string {
	var sb strings.Builder
	sb.WriteString(fmt.Sprintf("%-8s %-20s %-12s %s\n", "ID", "Title", "State", "Updated"))
	sb.WriteString(strings.Repeat("─", 50) + "\n")
	for _, row := range m.issueRows {
		title := row[1]
		if len(title) > 20 {
			title = title[:17] + "..."
		}
		sb.WriteString(fmt.Sprintf("%-8s %-20s %-12s %s\n", row[0], title, row[2], row[3]))
	}
	return sb.String()
}

// renderAgents formats the agents table.
func (m Model) renderAgents() string {
	var sb strings.Builder
	sb.WriteString(fmt.Sprintf("%-10s %-10s %-8s %s\n", "Name", "Status", "Issue", "Duration"))
	sb.WriteString(strings.Repeat("─", 40) + "\n")
	for _, row := range m.agentRows {
		sb.WriteString(fmt.Sprintf("%-10s %-10s %-8s %s\n", row[0], row[1], row[2], row[3]))
	}
	return sb.String()
}

// renderEvents formats the event stream as a scrollable list.
func (m Model) renderEvents() string {
	return strings.Join(m.eventLines, "\n")
}
