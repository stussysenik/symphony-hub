// theme.go — Color palette and lipgloss styles.
//
// Responsibility: Define all visual styling in one place. Every color,
// border style, and text decoration used in the TUI is defined here.
// This makes it easy to tweak the visual appearance without hunting
// through rendering code, and enables future theme switching.
//
// Design note: Colors use ANSI 256 codes for broad terminal compatibility.
// lipgloss automatically adapts colors to the terminal's color profile
// (truecolor, 256, 16, or no color).
package main

import "github.com/charmbracelet/lipgloss"

// Theme holds all styled components for the TUI.
// Grouped by purpose for easy discovery.
type Theme struct {
	// Pane chrome
	ActiveBorder   lipgloss.Style
	InactiveBorder lipgloss.Style
	PaneHeader     lipgloss.Style

	// Top-level chrome
	Title     lipgloss.Style
	StatusBar lipgloss.Style

	// Overlays
	ProjectOverlay lipgloss.Style
	HelpOverlay    lipgloss.Style

	// Text styles
	Dim     lipgloss.Style
	Bold    lipgloss.Style
	Success lipgloss.Style
	Warning lipgloss.Style
	Error   lipgloss.Style
	Info    lipgloss.Style

	// Colors (raw values for component-level styling)
	AccentColor     lipgloss.Color
	DimColor        lipgloss.Color
	SuccessColor    lipgloss.Color
	WarningColor    lipgloss.Color
	ErrorColor      lipgloss.Color
	InfoColor       lipgloss.Color
	BackgroundColor lipgloss.Color
}

// DefaultTheme returns the standard Symphony Hub color scheme.
// Inspired by modern terminal tools like lazygit and k9s.
func DefaultTheme() Theme {
	accent := lipgloss.Color("39")     // Bright blue
	dim := lipgloss.Color("240")       // Gray
	success := lipgloss.Color("42")    // Green
	warning := lipgloss.Color("226")   // Yellow
	errorC := lipgloss.Color("196")    // Red
	info := lipgloss.Color("75")       // Cyan
	highlight := lipgloss.Color("205") // Pink

	return Theme{
		ActiveBorder: lipgloss.NewStyle().
			Border(lipgloss.RoundedBorder()).
			BorderForeground(accent).
			Padding(0, 1),

		InactiveBorder: lipgloss.NewStyle().
			Border(lipgloss.RoundedBorder()).
			BorderForeground(dim).
			Padding(0, 1),

		PaneHeader: lipgloss.NewStyle().
			Bold(true).
			Foreground(accent),

		Title: lipgloss.NewStyle().
			Bold(true).
			Foreground(highlight).
			Padding(0, 1),

		StatusBar: lipgloss.NewStyle().
			Foreground(dim),

		ProjectOverlay: lipgloss.NewStyle().
			Border(lipgloss.DoubleBorder()).
			BorderForeground(highlight).
			Padding(1, 2),

		HelpOverlay: lipgloss.NewStyle().
			Border(lipgloss.DoubleBorder()).
			BorderForeground(accent).
			Padding(1, 2),

		Dim:     lipgloss.NewStyle().Foreground(dim),
		Bold:    lipgloss.NewStyle().Bold(true),
		Success: lipgloss.NewStyle().Foreground(success),
		Warning: lipgloss.NewStyle().Foreground(warning),
		Error:   lipgloss.NewStyle().Foreground(errorC),
		Info:    lipgloss.NewStyle().Foreground(info),

		AccentColor:  accent,
		DimColor:     dim,
		SuccessColor: success,
		WarningColor: warning,
		ErrorColor:   errorC,
		InfoColor:    info,
	}
}
