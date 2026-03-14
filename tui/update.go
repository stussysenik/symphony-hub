// update.go — Bubbletea Update() function.
//
// Responsibility: Handle all messages (key presses, window resizes, ticks)
// and return the updated Model + any follow-up commands. In the Elm
// Architecture, Update is the ONLY place where state changes happen.
// This makes state transitions predictable and easy to debug.
package main

import (
	tea "github.com/charmbracelet/bubbletea"
)

// Update processes incoming messages and returns the updated model.
// Every key press, window resize, and timer tick flows through here.
func (m Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {

	// Window resize — bubbletea sends this on startup and whenever
	// the terminal dimensions change.
	case tea.WindowSizeMsg:
		m.windowWidth = msg.Width
		m.windowHeight = msg.Height
		return m, nil

	// Key press — all keyboard input is handled here.
	case tea.KeyMsg:
		switch msg.String() {

		// Quit: q or ctrl+c exits the program
		case "q", "ctrl+c":
			m.quitting = true
			return m, tea.Quit

		// Tab / shift+tab: cycle through panes
		case "tab":
			m.activePane = (m.activePane + 1) % PaneCount
			return m, nil

		case "shift+tab":
			m.activePane = (m.activePane - 1 + PaneCount) % PaneCount
			return m, nil

		// Number keys: jump directly to a pane
		case "1":
			m.activePane = PaneIssues
			return m, nil
		case "2":
			m.activePane = PaneAgents
			return m, nil
		case "3":
			m.activePane = PaneEvents
			return m, nil
		}
	}

	return m, nil
}
