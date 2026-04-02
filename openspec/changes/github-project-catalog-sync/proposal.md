## Why

The hub could fan out initiatives across configured repos, but it still relied
on hand-maintained repo inventory. That left the wider GitHub fleet outside the
same operator surface and made cross-repo work harder to scale.

## What Changes

- add a GitHub-driven `sync-projects` command that imports repo metadata into a
  catalog inside `projects.yml`
- preserve the active `projects` runtime set while storing wider fleet
  discovery under `catalog.projects`
- allow optional cloning of missing repos during sync so cataloged repos can
  become diagnosis-ready immediately
- let intake and initiative resolve repo definitions from either the managed
  runtime set or the synced catalog
- allow a shared `--linear-project-slug` override for initiative/intake so
  cross-repo issue generation can work before every repo has bespoke mapping

## Impact

- operators get one source of truth for both active runtime repos and discovered
  fleet inventory
- cross-repo initiatives can scale beyond the small hand-curated runtime list
- applied syncs can refresh workflows and local checkouts in one pass
- the system keeps a hard boundary between discoverable repos and repos that
  are safe to launch as active Symphony runtimes
