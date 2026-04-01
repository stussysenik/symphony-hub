
## Implementation Approach

### Execution order
1. Read attached screenshots and issue context.
2. Reproduce the current behavior before changing code.
3. Find the exact change surface and keep the diff minimal.
4. Implement in dependency order.
5. Test with concrete commands and the affected user flow.
6. Document the outcome in repo-local issue notes when the repo already uses them.

### Commit convention
Use conventional commits: `type(scope): description`
- `fix(tags): resolve Instagram tag defaulting to placeholder values`
- `feat(search): add semantic search with embeddings`
- `style(tabs): update secondary highlight color on active tab`
- `docs(progress): add CRE-6 resolution details`

### Documentation per issue

If the repository already maintains these files, append concise issue notes:

**PROGRESS.md**
```
## {{ issue.identifier }}: {{ issue.title }}
- Status: Completed
- Files changed: (list with +/- counts)
- Summary: (1-2 sentences)
- Screenshot: ![](path/to/verification-screenshot.png)
```

**LEARNING.md**
```
## {{ issue.identifier }}: {{ issue.title }}
- Root cause: (what was actually wrong)
- Fix pattern: (reusable for future issues)
- Concepts: (specific technical concepts used)
```

### Verification
- Start the dev server when the task changes runtime behavior.
- Test the user flow described by the issue.
- Capture a screenshot for UI changes.
- Check console and server logs for errors.
- Record validation evidence in the Linear workpad.
