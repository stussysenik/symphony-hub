// projects.go — Project switcher pane component.
//
// Responsibility: Display a list of configured projects and allow the user
// to switch between them. The active project determines which Linear issues
// and agent data are shown in the other panes.
//
// Architecture note: Project data comes from projects.yml parsed at startup.
// Switching projects triggers a data refresh in the parent model — the
// Linear client re-fetches with the new project's slug, and the log parser
// switches to the new project's log file.
package components

import (
	"fmt"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

// Project represents a configured Symphony project.
type Project struct {
	Name             string
	GitHubURL        string
	LinearProjectSlug string
	MaxAgents        int
}

// ProjectSwitchedMsg is sent when the user switches to a different project.
// The parent model listens for this to trigger data refresh.
type ProjectSwitchedMsg struct {
	Project Project
}

// ProjectsModel manages the project switcher pane state.
type ProjectsModel struct {
	projects []Project
	cursor   int  // which project is highlighted
	active   int  // which project is currently selected
	width    int
	height   int
	focused  bool
}

// NewProjectsModel creates a ProjectsModel with empty data.
func NewProjectsModel() ProjectsModel {
	return ProjectsModel{
		projects: []Project{},
		cursor:   0,
		active:   0,
	}
}

// SetProjects replaces the project list.
func (m *ProjectsModel) SetProjects(projects []Project) {
	m.projects = projects
}

// ActiveProject returns the currently selected project, or nil if none.
func (m ProjectsModel) ActiveProject() *Project {
	if len(m.projects) == 0 {
		return nil
	}
	return &m.projects[m.active]
}

// SetSize updates the pane dimensions.
func (m *ProjectsModel) SetSize(w, h int) {
	m.width = w
	m.height = h
}

// SetFocused marks whether this pane has keyboard focus.
func (m *ProjectsModel) SetFocused(focused bool) {
	m.focused = focused
}

// Init satisfies the tea.Model interface.
func (m ProjectsModel) Init() tea.Cmd {
	return nil
}

// Update handles key events when focused.
func (m ProjectsModel) Update(msg tea.Msg) (ProjectsModel, tea.Cmd) {
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
			if m.cursor < len(m.projects)-1 {
				m.cursor++
			}
		// Enter selects the highlighted project as active
		case "enter":
			if m.cursor < len(m.projects) {
				m.active = m.cursor
				return m, func() tea.Msg {
					return ProjectSwitchedMsg{Project: m.projects[m.active]}
				}
			}
		}
	}
	return m, nil
}

// View renders the project list.
func (m ProjectsModel) View() string {
	var sb strings.Builder

	headerStyle := lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("252"))
	sb.WriteString(headerStyle.Render(" Projects") + "\n")
	sb.WriteString(strings.Repeat("─", min(m.width, 40)) + "\n")

	if len(m.projects) == 0 {
		dimStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("240"))
		sb.WriteString(dimStyle.Render(" No projects configured"))
		return sb.String()
	}

	for i, project := range m.projects {
		// Mark the active project with an arrow
		prefix := "  "
		if i == m.active {
			prefix = "→ "
		}

		line := fmt.Sprintf("%s%s", prefix, project.Name)

		if i == m.cursor && m.focused {
			selectedStyle := lipgloss.NewStyle().
				Background(lipgloss.Color("39")).
				Foreground(lipgloss.Color("0"))
			sb.WriteString(selectedStyle.Render(line))
		} else if i == m.active {
			activeStyle := lipgloss.NewStyle().
				Foreground(lipgloss.Color("42")).
				Bold(true)
			sb.WriteString(activeStyle.Render(line))
		} else {
			sb.WriteString(line)
		}
		sb.WriteString("\n")
	}

	if m.focused {
		dimStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("240"))
		sb.WriteString("\n" + dimStyle.Render(" Enter: select project"))
	}

	return sb.String()
}
