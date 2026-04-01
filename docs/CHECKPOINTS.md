# Checkpoints

Local checkpoints make the operator layer resumable without turning the repo itself into a pile of ad hoc notes.

## What a checkpoint is

A checkpoint is a timestamped snapshot of:
- `symphony-hub` git state
- the configured Symphony engine fork/upstream reference
- runtime launcher status, workspace inventory, and recent log tails
- Linear queue hygiene output when API access is available

Checkpoints are written to the local `checkpoints/` directory and are gitignored.

## Why this exists

Linear workpads already persist per-issue execution state.
What was missing was operator-state persistence:
- what repo state the hub was in
- what engine fork/upstream it pointed at
- what workspaces/logs were active
- what the queue looked like at a handoff point

That is the gap checkpoints fill.

## Usage

```bash
./launch.sh sources
./launch.sh checkpoint
./launch.sh checkpoint pre-review
./launch.sh checkpoint before-engine-sync
```

Each checkpoint creates a timestamped directory and refreshes `checkpoints/latest`.

## Resume flow

When continuing work from a checkpoint:

1. Read `SUMMARY.md`.
2. Inspect `hub/git-status.txt`.
3. Inspect `engine/git-status.txt` and the configured upstream/fork references.
4. Read `runtime/launch-status.txt`.
5. Read `linear/audit.txt`.
6. Run `./launch.sh sources` for a fresh topology readout.
7. Resume the specific issue from its Linear workpad and workspace.

## Source of truth

- Linear workpad: per-issue execution truth
- `projects.yml`: runtime configuration truth
- checkpoint snapshot: local operator handoff truth
