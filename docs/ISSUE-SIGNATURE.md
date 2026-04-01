# Issue Signature

`symphony-hub` now treats Linear issue structure as a first-class operator
contract, not just a template suggestion.

Canonical source files:

- `issue-signature.yml`: section order, aliases, placeholders, and `Todo` gate
- `issue_signature.py`: parser, renderer, formatter, and readiness evaluator

## Required `Todo` Shape

An issue is only `Todo`-ready when it has concrete, non-placeholder content for:

- `Context`
- `Problem`
- `Desired Outcome`
- `Acceptance Criteria`
- `Validation`
- `Assets`

`Acceptance Criteria` and `Validation` must contain real checklist items.

## Hot Paths

These commands all use the same signature contract:

- `./launch.sh intake --project <name> --prompt "..."`: drafts new issues in the canonical shape
- `./launch.sh issuefmt --project <name> --issue <ID>`: formats and lints an existing Linear issue
- `./launch.sh audit`: flags `Todo` issues that are structurally unready or formatting-drifted
- `./launch.sh diagnose --project <name> --issue <ID>`: diagnoses existing issues and includes signature readiness in the decision

## Formatting Behavior

`issuefmt` behaves like a small Prettier for Linear issues:

- rewrites recognized headings into canonical order
- normalizes heading names through aliases
- inserts required placeholder sections when the issue is incomplete
- preserves the managed intake block
- preserves unknown extra sections instead of deleting them

Use `--check` when you want a hard pass/fail signal:

```bash
./launch.sh issuefmt --project mymind-clone-web --issue CRE-123 --check
```

Use `--apply` when you want to rewrite the Linear body into canonical form:

```bash
./launch.sh issuefmt --project mymind-clone-web --issue CRE-123 --apply
```

## Operator Rule

Do not move an issue to `Todo` just because the idea is good.
Move it to `Todo` only when the signature is clean and the issue is still
relevant on current `main`.
