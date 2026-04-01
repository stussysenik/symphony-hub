## Why

Linear issue structure was documented but not enforced. That left too much room
for vague issue bodies, inconsistent headings, and `Todo` items that looked
active without being agent-ready.

## What Changes

- add a canonical issue signature file for required sections, aliases, and `Todo` gating
- add a shared formatter/linter that behaves like a small Prettier for Linear issues
- thread that signature into intake, audit, and diagnosis so the same contract is used everywhere

## Impact

- operators get one obvious path for cleaning up issue bodies
- `Todo` becomes a harder, more reliable execution gate
- queue hygiene can surface structurally bad issues instead of only stale ones
