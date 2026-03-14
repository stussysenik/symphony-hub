// events.go — Event stream pane component.
//
// Responsibility: Display a scrollable log of agent events, newest at the
// bottom. Events are color-coded by type: green for success, yellow for
// state changes, red for errors, gray for info.
//
// Architecture note: Events come from the log parser which tails Symphony's
// log files. The viewport auto-scrolls to the bottom when new events arrive,
// but the user can scroll up to review history.
package components

import (
	"fmt"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

// Event represents a parsed agent event from Symphony logs.
type Event struct {
	Timestamp string
	Type      string // "info", "state_change", "success", "error", "file_change"
	Message   string
}

// EventsModel manages the events pane state.
type EventsModel struct {
	events    []Event
	offset    int  // scroll offset (0 = bottom/latest)
	width     int
	height    int
	focused   bool
}

// NewEventsModel creates an EventsModel with empty data.
func NewEventsModel() EventsModel {
	return EventsModel{
		events: []Event{},
		offset: 0,
	}
}

// SetEvents replaces the current event list.
func (m *EventsModel) SetEvents(events []Event) {
	m.events = events
	// Auto-scroll to bottom when new events arrive
	m.offset = 0
}

// AppendEvent adds a single event and auto-scrolls to bottom.
func (m *EventsModel) AppendEvent(event Event) {
	m.events = append(m.events, event)
	m.offset = 0
}

// SetSize updates the pane dimensions.
func (m *EventsModel) SetSize(w, h int) {
	m.width = w
	m.height = h
}

// SetFocused marks whether this pane has keyboard focus.
func (m *EventsModel) SetFocused(focused bool) {
	m.focused = focused
}

// Init satisfies the tea.Model interface.
func (m EventsModel) Init() tea.Cmd {
	return nil
}

// Update handles key events when focused.
func (m EventsModel) Update(msg tea.Msg) (EventsModel, tea.Cmd) {
	if !m.focused {
		return m, nil
	}

	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch msg.String() {
		// Scroll up through history
		case "up", "k":
			maxOffset := max(0, len(m.events)-m.visibleLines())
			if m.offset < maxOffset {
				m.offset++
			}
		// Scroll down toward latest
		case "down", "j":
			if m.offset > 0 {
				m.offset--
			}
		// Jump to bottom (latest events)
		case "G":
			m.offset = 0
		// Jump to top (oldest events)
		case "g":
			m.offset = max(0, len(m.events)-m.visibleLines())
		}
	}
	return m, nil
}

// visibleLines calculates how many event lines fit in the pane.
func (m EventsModel) visibleLines() int {
	// Reserve 2 lines for header
	visible := m.height - 3
	if visible < 1 {
		visible = 10
	}
	return visible
}

// eventStyle returns a lipgloss style based on event type.
func eventStyle(eventType string) lipgloss.Style {
	switch eventType {
	case "success":
		return lipgloss.NewStyle().Foreground(lipgloss.Color("42"))  // Green
	case "state_change":
		return lipgloss.NewStyle().Foreground(lipgloss.Color("226")) // Yellow
	case "error":
		return lipgloss.NewStyle().Foreground(lipgloss.Color("196")) // Red
	case "file_change":
		return lipgloss.NewStyle().Foreground(lipgloss.Color("75"))  // Cyan
	default:
		return lipgloss.NewStyle().Foreground(lipgloss.Color("252")) // Light gray
	}
}

// View renders the event stream.
func (m EventsModel) View() string {
	var sb strings.Builder

	headerStyle := lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("252"))
	sb.WriteString(headerStyle.Render(" Event Stream") + "\n")
	sb.WriteString(strings.Repeat("─", min(m.width, 60)) + "\n")

	if len(m.events) == 0 {
		dimStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("240"))
		sb.WriteString(dimStyle.Render(" Waiting for events..."))
		return sb.String()
	}

	visible := m.visibleLines()
	// Calculate the window of events to show
	endIdx := len(m.events) - m.offset
	startIdx := endIdx - visible
	if startIdx < 0 {
		startIdx = 0
	}
	if endIdx > len(m.events) {
		endIdx = len(m.events)
	}

	for i := startIdx; i < endIdx; i++ {
		event := m.events[i]
		style := eventStyle(event.Type)
		timestamp := lipgloss.NewStyle().Foreground(lipgloss.Color("240")).Render(event.Timestamp)
		line := fmt.Sprintf(" %s %s", timestamp, style.Render(event.Message))
		sb.WriteString(line + "\n")
	}

	// Scroll indicator
	if m.offset > 0 {
		dimStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("240"))
		sb.WriteString(dimStyle.Render(fmt.Sprintf(" ↓ %d more events below", m.offset)))
	}

	return sb.String()
}
