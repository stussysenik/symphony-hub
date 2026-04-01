## Overview

The system needs one canonical issue-signature contract that every operator
path can consume:

- `issue-signature.yml` defines section order, aliases, placeholders, and
  `Todo` requirements
- `issue_signature.py` parses, formats, and evaluates issue bodies
- `linear-issuefmt.sh` exposes the contract directly to operators
- `linear-intake.sh`, `linear-audit.sh`, and `linear-diagnose.sh` import the
  same helper instead of keeping separate heading rules

## Decisions

### Preserve extra sections

Formatting should never delete user-authored sections. Unknown sections stay in
the body after the canonical signature sections.

### Preserve managed intake blocks

The intake block remains machine-managed and stable. Formatting can move it, but
not discard it.

### Separate semantic readiness from style drift

`Todo` readiness and canonical formatting are related but not identical:

- `todo-unready-signature`: required sections are missing or still placeholders
- `todo-needs-format`: the issue is not in canonical order/style

This lets the board show whether a problem is about missing substance, or only
about formatting drift.
