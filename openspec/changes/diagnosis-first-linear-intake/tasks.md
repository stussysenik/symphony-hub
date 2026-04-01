## 1. Intake Command

- [x] 1.1 Add a new `./launch.sh intake` command.
- [x] 1.2 Implement a diagnosis-first `linear-intake.sh` helper.
- [x] 1.3 Persist intake artifacts locally under a git-ignored report root.
- [x] 1.4 Support refreshing an existing issue without overwriting the human-authored body.

## 2. Draft Quality

- [x] 2.1 Include repo/default-branch diagnosis in the draft output.
- [x] 2.2 Include code evidence with line references and LOC.
- [x] 2.3 Include authorization / restriction signals in the draft output.
- [x] 2.4 Include related Linear issue hints for duplicate/supersession checks.
- [x] 2.5 Surface project-specific writable/restricted paths and required checks.

## 3. Guardrails

- [x] 3.1 Keep dry-run as the default behavior.
- [x] 3.2 Require explicit `--apply` for any issue creation or refresh mutation and an explicit `--issue` target for refresh.
- [x] 3.3 Default created issues to `Triage` unless the operator overrides it.
- [x] 3.4 Keep remote fetch skippable via `--no-fetch`.
- [x] 3.5 Keep the richer compile path bounded and fall back deterministically when it does not complete in time.

## 4. Docs

- [x] 4.1 Document the intake loop in README and operations docs.
- [x] 4.2 Update the docs map to point operators to the new intake surface.
