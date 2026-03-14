// help.go — Help overlay component.
//
// Responsibility: Render a modal overlay showing all keyboard shortcuts.
// Toggled with '?' key. The overlay renders on top of the pane layout,
// blocking other input until dismissed with '?' or Escape.
package main

import (
	"strings"

	"github.com/charmbracelet/lipgloss"
)

// helpBindings defines all keyboard shortcuts grouped by category.
var helpBindings = []helpSection{
	{
		Title: "Navigation",
		Bindings: []helpBinding{
			{Key: "Tab / Shift+Tab", Desc: "Cycle through panes"},
			{Key: "1 / 2 / 3", Desc: "Jump to Issues / Agents / Events"},
			{Key: "j / Down", Desc: "Move cursor down"},
			{Key: "k / Up", Desc: "Move cursor up"},
			{Key: "g / G", Desc: "Jump to top / bottom (Events)"},
		},
	},
	{
		Title: "Actions",
		Bindings: []helpBinding{
			{Key: "p", Desc: "Toggle project switcher"},
			{Key: "Enter", Desc: "Select project (in switcher)"},
			{Key: "r", Desc: "Manual data refresh"},
		},
	},
	{
		Title: "General",
		Bindings: []helpBinding{
			{Key: "?", Desc: "Toggle this help"},
			{Key: "Esc", Desc: "Close overlay"},
			{Key: "q / Ctrl+C", Desc: "Quit"},
		},
	},
}

type helpSection struct {
	Title    string
	Bindings []helpBinding
}

type helpBinding struct {
	Key  string
	Desc string
}

// renderHelp builds the help overlay content string.
func renderHelp() string {
	var sb strings.Builder

	titleStyle := lipgloss.NewStyle().
		Bold(true).
		Foreground(lipgloss.Color("205"))

	keyStyle := lipgloss.NewStyle().
		Foreground(lipgloss.Color("39")).
		Bold(true)

	descStyle := lipgloss.NewStyle().
		Foreground(lipgloss.Color("252"))

	sectionStyle := lipgloss.NewStyle().
		Foreground(lipgloss.Color("226")).
		Bold(true)

	sb.WriteString(titleStyle.Render("Symphony Hub — Keyboard Shortcuts"))
	sb.WriteString("\n\n")

	for _, section := range helpBindings {
		sb.WriteString(sectionStyle.Render(section.Title))
		sb.WriteString("\n")

		for _, binding := range section.Bindings {
			key := keyStyle.Render(padRight(binding.Key, 20))
			desc := descStyle.Render(binding.Desc)
			sb.WriteString("  " + key + " " + desc + "\n")
		}
		sb.WriteString("\n")
	}

	dimStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("240"))
	sb.WriteString(dimStyle.Render("Press ? or Esc to close"))

	return sb.String()
}

// padRight pads a string to the given width with spaces.
func padRight(s string, width int) string {
	if len(s) >= width {
		return s
	}
	return s + strings.Repeat(" ", width-len(s))
}
