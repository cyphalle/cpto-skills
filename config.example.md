# Team config

Every skill in this repository reads its team-specific facts from one file. Copy this file to
`~/.claude/skills/config.md` and fill it in. A skill never guesses a handle, a branch or a
board ID: when a value is missing here, the skill stops and says which value it needs.

## Owners

One owner per domain. The owner signs off on choices in their domain. Skills route reviews,
handoffs and ratification requests from this table.

| Domain | Owner | GitHub handle | Review mode |
|---|---|---|---|
| Backend, API, schema migrations, SQL | `<name>` | `<handle>` | upstream or on the diff |
| Frontend, app, infra, CI | `<name>` | `<handle>` | upstream or on the diff |
| Data: reference table contents, seeds, sources | `<name>` | `<handle>` | ratify on the diff only |
| Methodology: formulas, thresholds, units | `<name>` | `<handle>` | ratify on the diff only |
| Product and tech lead (default assignee) | `<name>` | `<handle>` | |

"Ratify on the diff only" marks owners who answer a written choice better than an open
question. Skills never send them an open question upstream. They decide, write the choice
with the rejected alternative, and ask for "ratify or correct" in the pull request.

## Repository

```yaml
repo: <owner>/<repo>
base_branch: develop          # the branch feature work merges into
release_branch: main          # the branch a release PR targets
branch_convention: "<scope>/<type>/<description>"
scopes: [backend, frontend, infra, docs]
types: [feat, fix, chore, docs, refactor, test, perf]
commit_convention: "<scope>/<type>: <message>"
```

## Board

```yaml
project_number: <n>           # GitHub Project (v2) that holds the Status field
status_helper: ~/.claude/scripts/gh-issue-status.sh   # "<Status>" <issue numbers...>
statuses: [To research, Research to review, To design, Design to review, To dev,
           In Progress, Dev to review, Deployed DEV, Deployed PROD]
```

## Checks per layer

| Changed paths | Command that matches CI |
|---|---|
| `backend/`, `crates/` | `cargo fmt --all --check && cargo clippy --all-targets -- -D warnings && cargo nextest run` |
| `frontend/` | `pnpm type-check && pnpm lint:check && pnpm format:check && pnpm test` |
| `infrastructure/` | `terraform fmt -check && terraform validate` |
