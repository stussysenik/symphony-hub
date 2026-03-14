// agents.go — Active agents status pane component.
//
// Responsibility: Display a table of running Symphony agents with their name,
// status, current issue, and duration. Status is color-coded: green for
// working, yellow for idle, red for errored.
//
// Architecture note: Agent data is derived from two sources — the Linear
// issues list (which issues are In Progress) and the log parser (which
// agents are actively running). The parent model combines these sources
// and calls SetAgents() with the merged data.
package components

import (
	"fmt"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

// Agent represents an active Symphony agent for display.
type Agent struct {
	Name     string
	Status   string // "Working", "Idle", "Error"
	Issue    string // Issue identifier or "—"
	Duration string // How long the agent has been running
}

// AgentsModel manages the agents pane state.
type AgentsModel struct {
	agents  []Agent
	cursor  int
	width   int
	height  int
	focused bool
}

// NewAgentsModel creates an AgentsModel with empty data.
func NewAgentsModel() AgentsModel {
	return AgentsModel{
		agents: []Agent{},
		cursor: 0,
	}
}

// SetAgents replaces the current agent list.
func (m *AgentsModel) SetAgents(agents []Agent) {
	m.agents = agents
	if m.cursor >= len(agents) {
		m.cursor = max(0, len(agents)-1)
	}
}

// SetSize updates the pane dimensions.
func (m *AgentsModel) SetSize(w, h int) {
	m.width = w
	m.height = h
}

// SetFocused marks whether this pane has keyboard focus.
func (m *AgentsModel) SetFocused(focused bool) {
	m.focused = focused
}

// Init satisfies the tea.Model interface.
func (m AgentsModel) Init() tea.Cmd {
	return nil
}

// Update handles key events when focused.
func (m AgentsModel) Update(msg tea.Msg) (AgentsModel, tea.Cmd) {
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
			if m.cursor < len(m.agents)-1 {
				m.cursor++
			}
		}
	}
	return m, nil
}

// statusStyle returns a lipgloss style based on agent status.
// Color-coding makes it easy to spot problems at a glance.
func statusStyle(status string) lipgloss.Style {
	switch status {
	case "Working":
		return lipgloss.NewStyle().Foreground(lipgloss.Color("42")) // Green
	case "Idle":
		return lipgloss.NewStyle().Foreground(lipgloss.Color("226")) // Yellow
	case "Error":
		return lipgloss.NewStyle().Foreground(lipgloss.Color("196")) // Red
	default:
		return lipgloss.NewStyle().Foreground(lipgloss.Color("252"))
	}
}

// View renders the agents table.
func (m AgentsModel) View() string {
	var sb strings.Builder

	header := fmt.Sprintf(" %-12s %-10s %-10s %s", "Name", "Status", "Issue", "Duration")
	headerStyle := lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("252"))
	sb.WriteString(headerStyle.Render(header) + "\n")
	sb.WriteString(strings.Repeat("─", min(m.width, 50)) + "\n")

	if len(m.agents) == 0 {
		dimStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("240"))
		sb.WriteString(dimStyle.Render(" No agents running"))
		return sb.String()
	}

	for i, agent := range m.agents {
		statusText := statusStyle(agent.Status).Render(fmt.Sprintf("%-10s", agent.Status))
		line := fmt.Sprintf(" %-12s %s %-10s %s", agent.Name, statusText, agent.Issue, agent.Duration)

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
