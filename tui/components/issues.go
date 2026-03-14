// issues.go — Linear issues list pane component.
//
// Responsibility: Display a table of Linear issues with their ID, title,
// state, and last update time. This is a bubbletea sub-model: it implements
// the tea.Model interface so the parent Model can embed and delegate to it.
//
// Architecture note: In bubbletea, complex UIs are built by composing
// sub-models. Each sub-model manages its own state and rendering, but the
// parent coordinates which sub-model receives focus (key events).
package components

import (
	"fmt"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

// Issue represents a Linear issue for display in the table.
type Issue struct {
	ID      string
	Title   string
	State   string
	Updated string
}

// IssuesModel manages the issues list pane state.
type IssuesModel struct {
	issues  []Issue
	cursor  int // which row is highlighted
	width   int
	height  int
	focused bool
}

// NewIssuesModel creates an IssuesModel with empty data.
// Data is populated later via SetIssues().
func NewIssuesModel() IssuesModel {
	return IssuesModel{
		issues: []Issue{},
		cursor: 0,
	}
}

// SetIssues replaces the current issue list with new data.
func (m *IssuesModel) SetIssues(issues []Issue) {
	m.issues = issues
	if m.cursor >= len(issues) {
		m.cursor = max(0, len(issues)-1)
	}
}

// SetSize updates the pane dimensions for rendering.
func (m *IssuesModel) SetSize(w, h int) {
	m.width = w
	m.height = h
}

// SetFocused marks whether this pane currently has keyboard focus.
func (m *IssuesModel) SetFocused(focused bool) {
	m.focused = focused
}

// Init satisfies the tea.Model interface. No initial commands needed.
func (m IssuesModel) Init() tea.Cmd {
	return nil
}

// Update handles key events when this pane is focused.
func (m IssuesModel) Update(msg tea.Msg) (IssuesModel, tea.Cmd) {
	if !m.focused {
		return m, nil
	}

	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch msg.String() {
		case "up", "k":
			if m.cursor > 0 {
				m.cursor--
			}
		case "down", "j":
			if m.cursor < len(m.issues)-1 {
				m.cursor++
			}
		}
	}
	return m, nil
}

// stateEmoji maps Linear issue states to visual indicators.
func stateEmoji(state string) string {
	switch state {
	case "Triage":
		return "[~]"
	case "Todo":
		return "[ ]"
	case "In Progress":
		return "[>]"
	case "Human Review":
		return "[?]"
	case "Merging":
		return "[=]"
	case "Rework":
		return "[!]"
	case "Done":
		return "[x]"
	case "Canceled", "Cancelled":
		return "[-]"
	default:
		return "[ ]"
	}
}

// View renders the issues table as a string.
func (m IssuesModel) View() string {
	var sb strings.Builder

	// Column header
	header := fmt.Sprintf(" %-8s %-22s %-5s %s", "ID", "Title", "State", "Updated")
	headerStyle := lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("252"))
	sb.WriteString(headerStyle.Render(header) + "\n")
	sb.WriteString(strings.Repeat("─", min(m.width, 60)) + "\n")

	if len(m.issues) == 0 {
		dimStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("240"))
		sb.WriteString(dimStyle.Render(" No issues loaded"))
		return sb.String()
	}

	for i, issue := range m.issues {
		title := issue.Title
		if len(title) > 22 {
			title = title[:19] + "..."
		}

		line := fmt.Sprintf(" %-8s %-22s %-5s %s", issue.ID, title, stateEmoji(issue.State), issue.Updated)

		if i == m.cursor && m.focused {
			selectedStyle := lipgloss.NewStyle().
				Background(lipgloss.Color("39")).
				Foreground(lipgloss.Color("0"))
			sb.WriteString(selectedStyle.Render(line))
		} else {
			sb.WriteString(line)
		}
		sb.WriteString("\n")
	}

	return sb.String()
}
