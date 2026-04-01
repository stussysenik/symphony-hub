# Linear Template Blueprints

These files are not imported automatically by Linear. Use them as the source of truth when creating Linear form templates in `Workspace settings -> Templates` or `Team settings -> Templates`.

Each template file includes:

- recommended form fields
- recommended default properties
- a description body you can paste into the template

The canonical issue contract is defined in [`../issue-signature.yml`](../issue-signature.yml).
Use these templates to start close to that shape, then run
`./launch.sh issuefmt --project <name> --issue <ID>` before moving work to `Todo`.

Recommended template set:

- [`bug-report.md`](bug-report.md)
- [`feature-request.md`](feature-request.md)
- [`tech-debt.md`](tech-debt.md)
- [`research-spike.md`](research-spike.md)
- [`agent-ready-project.md`](agent-ready-project.md)

For Symphony-driven teams:

- default new intake to `Triage`
- use `Todo` as the execution trigger
- keep labels minimal and consistent
- use `agent-ready-project.md` when you want the Linear issue itself to be the full execution spec
- run `./launch.sh issuefmt --project <name> --issue <ID>` before moving fuzzy existing issues to `Todo`
