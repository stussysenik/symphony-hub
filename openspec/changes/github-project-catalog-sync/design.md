## Overview

Repo discovery and repo execution should not be the same thing.

This change separates them:

- `projects`: active runtime repos with workflows, ports, and launch semantics
- `catalog.projects`: GitHub-discovered repos that can feed intake and
  initiatives, but are not started by `launch.sh start`

The new control loop is:

1. `sync-projects` imports GitHub metadata into `catalog.projects`
2. `initiative` or `intake` can target either managed projects or cataloged
   repos
3. issue creation still requires Linear mapping, either from the repo entry’s
   `linear_project_slug` or a shared runtime override

## Decisions

### Preserve active runtime isolation

Discovered repos do not automatically become launchable Symphony runtimes.
Keeping them in a separate catalog prevents broken workflow generation, phantom
ports, and launcher noise.

### Preserve manual policy edits

GitHub sync updates source-of-truth metadata such as slug, URL, branch, and
sync timestamps, but it preserves manual fields like:

- `repo_root`
- `linear_project_slug`
- `intake`
- `assets`

### Allow shared Linear override

Cross-repo initiatives often start before every repo has a dedicated Linear
project mapping. A shared `--linear-project-slug` override lets operators
create repo-local issues in one Linear project without mutating each cataloged
repo entry first.

### Optional cloning stays explicit

Some repo-backed flows need a local checkout immediately after discovery. The
sync command may clone missing repos, but only when the operator explicitly
requests that behavior or encodes it in catalog defaults.

### Applied sync refreshes workflows

Managed runtime projects still depend on generated workflow files. When sync
updates the active `projects` list, it should regenerate workflows during an
applied run so the runtime view stays consistent with config.

### Fail clearly when diagnosis cannot be grounded

Repo-backed intake and diagnosis still require:

- a local checkout at `repo_root`
- a Linear project slug, or an explicit override for intake/initiative

The system should report those gaps explicitly instead of silently degrading
into vague issue creation.
