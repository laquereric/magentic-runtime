# magentic-runtime

The local governed-flow runtime for The Magentic Stack.

## Workflow: mmg-gstack (role-based sprint)

This repo has the **mmg-gstack** role-skills installed as Claude Code slash commands
(under [`.claude/commands/`](.claude/commands/)). The principle: **define the role
before the task** — a role is a lens; the lens changes what you find.

**Sprint:** `think → plan → build → review → test → ship → reflect` — each stage feeds the next.

| Stage | Command(s) |
|---|---|
| think | `/think` (Framer) |
| plan | `/plan-eng-review` (Engineering Manager) · `/boundary-keeper` |
| build | `/build` (Builder) |
| review | `/review` (Reviewer) · `/cso` (Security Reviewer — OWASP + STRIDE, confidence ≥ 8) |
| test | `/qa` (QA Lead) |
| ship | `/ship` (Release Manager — gates → signed release_ready) |
| reflect | `/reflect` (Reflector) |

See [`.claude/gstack.md`](.claude/gstack.md) for the full role list. Managed by
`mmg-gstack` (`mmg-gstack apply .` reinstalls / updates the commands).
