// main.go — Entry point for Symphony Hub TUI.
//
// Responsibility: Parse CLI flags, load configuration from projects.yml,
// initialize the Model, and start the bubbletea program. This file does NOT
// contain any business logic, rendering, or message handling — those live in
// model.go, update.go, and view.go following the Elm Architecture pattern.
package main

import (
	"flag"
	"fmt"
	"os"

	tea "github.com/charmbracelet/bubbletea"
	"gopkg.in/yaml.v3"

	"symphony-hub/tui/components"
)

// Config mirrors the structure of projects.yml.
// Only the fields the TUI needs are included.
type Config struct {
	Defaults struct {
		MaxAgents int `yaml:"max_agents"`
	} `yaml:"defaults"`
	LogsRoot string          `yaml:"logs_root"`
	Projects []ProjectConfig `yaml:"projects"`
}

// ProjectConfig holds per-project settings from projects.yml.
type ProjectConfig struct {
	Name              string `yaml:"name"`
	GitHubURL         string `yaml:"github_url"`
	LinearProjectSlug string `yaml:"linear_project_slug"`
	MaxAgents         int    `yaml:"max_agents"`
}

func main() {
	// Parse CLI flags
	configPath := flag.String("config", "projects.yml", "Path to projects.yml configuration file")
	flag.Parse()

	// Load and parse projects.yml
	config, err := loadConfig(*configPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Warning: could not load config %s: %v\n", *configPath, err)
		fmt.Fprintf(os.Stderr, "Starting with placeholder data.\n\n")
		config = nil
	}

	// Initialize the model with loaded config
	m := NewModel(*configPath)

	// If config loaded successfully, populate projects from it
	if config != nil {
		projects := make([]components.Project, len(config.Projects))
		for i, p := range config.Projects {
			maxAgents := p.MaxAgents
			if maxAgents == 0 {
				maxAgents = config.Defaults.MaxAgents
			}
			projects[i] = components.Project{
				Name:              p.Name,
				GitHubURL:         p.GitHubURL,
				LinearProjectSlug: p.LinearProjectSlug,
				MaxAgents:         maxAgents,
			}
		}
		m.projects.SetProjects(projects)
		m.logsRoot = config.LogsRoot
	}

	// Read Linear API key from environment
	m.linearAPIKey = os.Getenv("LINEAR_API_KEY")

	// Create and run the bubbletea program
	p := tea.NewProgram(m, tea.WithAltScreen(), tea.WithMouseCellMotion())

	if _, err := p.Run(); err != nil {
		fmt.Fprintf(os.Stderr, "Error running Symphony Hub TUI: %v\n", err)
		os.Exit(1)
	}
}

// loadConfig reads and parses projects.yml.
func loadConfig(path string) (*Config, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("read %s: %w", path, err)
	}

	var config Config
	if err := yaml.Unmarshal(data, &config); err != nil {
		return nil, fmt.Errorf("parse %s: %w", path, err)
	}

	return &config, nil
}
