# Decisions: Why We Built Hub This Way

> Every architectural choice has a reason. This document captures the "why"
> behind Symphony Hub's design decisions so future contributors (or future us)
> understand the tradeoffs.

---

## Decision 1: Go + Charm for TUI

**Chose:** Go with Charm libraries (bubbletea, bubbles, lipgloss)
**Over:** Python (textual/rich), Rust (ratatui), another Elixir app, web dashboard

**Why:**

- **Single binary distribution** — `go build` produces one executable. No
  runtime dependencies, no `pip install`, no Docker. Copy the binary and run.
- **Cross-platform** — Same codebase compiles for macOS (ARM + Intel), Linux,
  Windows. Symphony users aren't all on macOS.
- **Charm ecosystem** — bubbletea provides the Elm Architecture for terminals
  (Model-Update-View). bubbles gives pre-built components (tables, viewports,
  text inputs). lipgloss handles styling. Together they're the most mature TUI
  framework available.
- **Not another web dashboard** — Symphony already has Phoenix LiveView
  dashboards. Adding another web UI would be redundant. A TUI serves the
  CLI-first workflow that terminal-native developers prefer.
- **Performance** — Go's goroutines handle concurrent data fetching (Linear API
  + log parsing + UI rendering) without blocking. Important for a responsive
  dashboard.

**Tradeoff:** Go's type system is less expressive than Rust's, and the Charm
ecosystem is newer than ncurses. But for a monitoring dashboard, Go's
simplicity wins over Rust's safety guarantees.

---

## Decision 2: SRP File Structure

**Chose:** One concern per file, even if files are small
**Over:** Monolithic files, feature-grouped modules

**Why:**

- **Navigability** — When you want to change how the view renders, you open
  `view.go`. When you want to change key handling, you open `update.go`. No
  searching through a 500-line file.
- **Elm Architecture alignment** — bubbletea follows Model-Update-View. Our
  file structure mirrors this: `model.go`, `update.go`, `view.go`. The code
  organization teaches the architecture pattern.
- **Diff-friendly** — Git diffs are cleaner when changes are isolated to
  single-purpose files. A UI change only touches `view.go`, not a monolith.
- **Parallel development** — Multiple contributors can work on different
  concerns without merge conflicts.

**Tradeoff:** More files means more `import` statements and more jumping
between files. For a project this size, the clarity benefit outweighs the
navigation cost.

---

## Decision 3: Beta Tags, Not Semver

**Chose:** `beta/descriptive-name` tags (e.g., `beta/foundation`, `beta/tui-scaffold`)
**Over:** Semantic versioning (v0.1.0, v0.2.0)

**Why:**

- **Closed beta, solo developer** — Semver communicates compatibility promises
  to downstream consumers. We have no downstream consumers yet. No one depends
  on our API stability.
- **Descriptive names** — `beta/vision-foundation` tells you what changed
  better than `v0.4.0`. During rapid development, descriptive tags are more
  useful than version numbers.
- **No false promises** — Publishing `v1.0.0` implies production readiness.
  We're not there. `beta/` prefix makes the status obvious.
- **Easy migration** — When we're ready for public release, we can start
  semver from v1.0.0. The beta tags remain as historical markers.

**Tradeoff:** Can't use semver-based tooling (dependabot, version bumpers).
Not a problem since we have no dependents.

---

## Decision 4: Linear as the Interface

**Chose:** Linear issues as the primary agent interface
**Over:** Custom UI, Slack integration, GitHub Issues, CLI commands

**Why:**

- **Existing integration** — Symphony already polls Linear. Building on this
  means zero new infrastructure.
- **Rich issue model** — Linear issues have titles, descriptions, states,
  labels, attachments, workpad comments, and relations. That's everything an
  agent needs as input.
- **Human-friendly** — Product managers and designers already use Linear. They
  can create issues for agents without learning new tools.
- **State machine built-in** — Linear's workflow states (Todo, In Progress,
  Done) map directly to agent lifecycle states.

**Tradeoff:** Tight coupling to Linear. If a team uses Jira or GitHub Issues,
they'd need a different integration. For now, Linear is the right choice for
our workflow.

---

## Decision 5: Separate Repository

**Chose:** `symphony-hub` as a separate repo from `open-ai-symphony`
**Over:** Adding Hub code directly to the Symphony repo

**Why:**

- **Wrapper vs. core** — Symphony Hub is a monitoring/control layer around
  Symphony. It doesn't modify Symphony's core behavior. Keeping it separate
  makes the dependency direction clear: Hub depends on Symphony, not vice versa.
- **Different languages** — Hub is primarily Go + shell scripts. Symphony is
  Elixir. Mixing them in one repo would confuse tooling (mix + go mod in one
  project).
- **Independent release cycle** — Hub can evolve faster than Symphony core.
  We can ship TUI improvements without touching Elixir code.
- **Clean boundaries** — Forces us to interact with Symphony through its
  defined interfaces (GraphQL API, log files, config files) rather than
  reaching into internals.

**Tradeoff:** When vision features require Symphony core changes (Layers 6-7),
we need coordinated changes across repos. Worth it for the clean separation.

---

## Decision 6: Vision / Screenshots Matter

**Chose:** Invest in visual asset support (attachments, screenshots, multimodal prompts)
**Over:** Keeping agents text-only

**Why:**

- **Agents can't implement what they can't see** — When a Linear issue says
  "match this mockup" but the mockup is an image attachment, text-only agents
  are flying blind. They guess at layouts, colors, and spacing.
- **Multimodal models exist** — OpenAI's models accept image inputs. We're
  leaving capability on the table by only sending text.
- **Real-world workflow** — Designers attach Figma exports and screenshots to
  Linear issues. That's how teams communicate visual requirements. Agents
  should participate in this workflow naturally.
- **Measurable improvement** — Visual context reduces iteration cycles. Instead
  of "implement, review, fix, review" it becomes "implement correctly the first
  time" because the agent can see the target.

**Tradeoff:** Image processing adds complexity (downloading, caching, format
handling) and increases API costs (multimodal tokens are more expensive). The
quality improvement in agent output justifies both.

---

## Decision 7: Conventional Commits

**Chose:** `type(scope): description` format
**Over:** Freeform commit messages

**Why:**

- **Scannable history** — `git log --oneline` immediately shows what changed
  and where: `feat(tui):`, `docs(research):`, `fix(vision):`.
- **Changelog generation** — Conventional commits can be parsed to auto-generate
  changelogs when we reach public release.
- **Scope as documentation** — The scope tells you which subsystem changed
  without reading the diff.

---

## Decision Summary

| Decision | Chose | Key Reason |
|----------|-------|------------|
| TUI framework | Go + Charm | Single binary, rich ecosystem |
| File structure | SRP (one concern per file) | Navigability, teaches architecture |
| Versioning | beta/ tags | Descriptive, no false promises |
| Agent interface | Linear issues | Existing integration, rich model |
| Repo structure | Separate repo | Wrapper vs. core separation |
| Visual support | Multimodal prompts | Agents see mockups, better output |
| Commit format | Conventional commits | Scannable, parseable history |
