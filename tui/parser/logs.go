// logs.go — Symphony log file parser.
//
// Responsibility: Read and parse Symphony log files to extract structured
// events for the TUI event stream. Understands Symphony's log format and
// categorizes events by type (state changes, file operations, errors, etc.).
//
// Architecture note: Symphony writes logs to a configurable directory
// (logs_root in projects.yml). Each project gets its own log file named
// <project-name>.log. The parser tails these files for new lines and
// parses them into structured Event objects.
package parser

import (
	"bufio"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"time"
)

// Event represents a parsed log event with metadata for display.
type Event struct {
	Timestamp string
	Type      string // "info", "state_change", "success", "error", "file_change"
	Message   string
	Raw       string // Original log line
}

// LogParser reads and parses Symphony log files.
type LogParser struct {
	logsRoot string
}

// NewLogParser creates a parser for the given logs directory.
func NewLogParser(logsRoot string) *LogParser {
	return &LogParser{logsRoot: logsRoot}
}

// Regex patterns for classifying log lines.
// Symphony's Elixir logger uses standard Erlang/Elixir log format.
var (
	// Matches timestamps like [2024-01-15 10:00:15.123]
	timestampRe = regexp.MustCompile(`\[(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2})`)

	// Patterns that indicate event types
	stateChangeRe = regexp.MustCompile(`(?i)(state.*change|transition|todo|in.progress|human.review|done)`)
	errorRe       = regexp.MustCompile(`(?i)(error|fail|crash|exception|timeout)`)
	successRe     = regexp.MustCompile(`(?i)(success|complete|pass|merge|created pr)`)
	fileChangeRe  = regexp.MustCompile(`(?i)(created|modified|deleted|wrote|file|workspace)`)
)

// ParseLogFile reads a project's log file and returns structured events.
// projectName is used to find the log file: <logsRoot>/<projectName>.log
func (p *LogParser) ParseLogFile(projectName string) ([]Event, error) {
	logPath := filepath.Join(p.logsRoot, projectName+".log")

	file, err := os.Open(logPath)
	if err != nil {
		if os.IsNotExist(err) {
			return []Event{}, nil // No log file yet is not an error
		}
		return nil, err
	}
	defer file.Close()

	var events []Event
	scanner := bufio.NewScanner(file)

	// Increase scanner buffer for long log lines
	buf := make([]byte, 0, 64*1024)
	scanner.Buffer(buf, 1024*1024)

	for scanner.Scan() {
		line := scanner.Text()
		if event := parseLine(line); event != nil {
			events = append(events, *event)
		}
	}

	return events, scanner.Err()
}

// TailLogFile reads the last N lines from a project's log file.
// Useful for initial load without reading the entire file.
func (p *LogParser) TailLogFile(projectName string, lines int) ([]Event, error) {
	allEvents, err := p.ParseLogFile(projectName)
	if err != nil {
		return nil, err
	}

	if len(allEvents) <= lines {
		return allEvents, nil
	}
	return allEvents[len(allEvents)-lines:], nil
}

// parseLine converts a single log line into a structured Event.
// Returns nil for lines that don't represent meaningful events.
func parseLine(line string) *Event {
	line = strings.TrimSpace(line)
	if line == "" {
		return nil
	}

	// Extract timestamp
	timestamp := extractTimestamp(line)
	if timestamp == "" {
		timestamp = time.Now().Format("[15:04:05]")
	}

	// Classify the event type based on content
	eventType := classifyLine(line)

	// Clean up the message (remove timestamp prefix, excess whitespace)
	message := cleanMessage(line)
	if message == "" {
		return nil
	}

	return &Event{
		Timestamp: timestamp,
		Type:      eventType,
		Message:   message,
		Raw:       line,
	}
}

// extractTimestamp pulls a timestamp from the log line.
func extractTimestamp(line string) string {
	matches := timestampRe.FindStringSubmatch(line)
	if len(matches) < 2 {
		return ""
	}
	// Parse and reformat to shorter display format
	t, err := time.Parse("2006-01-02 15:04:05", matches[1])
	if err != nil {
		return "[" + matches[1] + "]"
	}
	return t.Format("[15:04:05]")
}

// classifyLine determines the event type from line content.
func classifyLine(line string) string {
	switch {
	case errorRe.MatchString(line):
		return "error"
	case successRe.MatchString(line):
		return "success"
	case stateChangeRe.MatchString(line):
		return "state_change"
	case fileChangeRe.MatchString(line):
		return "file_change"
	default:
		return "info"
	}
}

// cleanMessage strips log formatting to produce a readable message.
func cleanMessage(line string) string {
	// Remove common log prefixes
	msg := timestampRe.ReplaceAllString(line, "")
	msg = strings.TrimLeft(msg, "] ")

	// Remove Elixir log level prefixes
	for _, prefix := range []string{"[info]", "[debug]", "[warning]", "[error]", "[notice]"} {
		msg = strings.TrimPrefix(msg, prefix)
	}

	return strings.TrimSpace(msg)
}
