// main.go — Entry point for Symphony Hub TUI.
//
// Responsibility: Parse CLI flags, initialize the Model, and start the
// bubbletea program. This file does NOT contain any business logic, rendering,
// or message handling — those live in model.go, update.go, and view.go
// following the Elm Architecture pattern (Model-Update-View).
package main

import (
	"flag"
	"fmt"
	"os"

	tea "github.com/charmbracelet/bubbletea"
)

func main() {
	// Parse CLI flags
	configPath := flag.String("config", "projects.yml", "Path to projects.yml configuration file")
	flag.Parse()

	// Initialize the model with config path
	m := NewModel(*configPath)

	// Create and run the bubbletea program.
	// WithAltScreen uses the alternate terminal buffer so the TUI doesn't
	// pollute the user's scrollback history.
	// WithMouseCellMotion enables mouse tracking for future click support.
	p := tea.NewProgram(m, tea.WithAltScreen(), tea.WithMouseCellMotion())

	if _, err := p.Run(); err != nil {
		fmt.Fprintf(os.Stderr, "Error running Symphony Hub TUI: %v\n", err)
		os.Exit(1)
	}
}
