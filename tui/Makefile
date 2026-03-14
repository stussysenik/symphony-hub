# Makefile — Build, run, and install targets for Symphony Hub TUI.
#
# Usage:
#   make build    — Compile the binary
#   make run      — Build and run with default config
#   make install  — Copy binary to /usr/local/bin
#   make clean    — Remove build artifacts

BINARY_NAME := symphony-hub
BUILD_DIR := .
GO_FILES := $(shell find . -name '*.go' -type f)

.PHONY: build run install clean

# Build the binary
build: $(GO_FILES)
	go build -o $(BINARY_NAME) .
	@echo "Built $(BINARY_NAME)"

# Build and run with default config (looks for ../projects.yml)
run: build
	./$(BINARY_NAME) --config ../projects.yml

# Install to /usr/local/bin for system-wide access
install: build
	cp $(BINARY_NAME) /usr/local/bin/$(BINARY_NAME)
	@echo "Installed $(BINARY_NAME) to /usr/local/bin/"

# Remove build artifacts
clean:
	rm -f $(BINARY_NAME)
	go clean
	@echo "Cleaned"
