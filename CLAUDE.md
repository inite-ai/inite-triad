@AGENTS.md

## Claude Code

- Skills: `/contribute` (idea → routed to the right repo → spec → PR) and
  `/spec-idea` (idea → filed issue, no code). Both live in `.claude/skills/`.
- Ask before any `docker compose up` / `pull` (ground rule 4); `docker compose
  --env-file .env.example config -q`, `shellcheck` and `actionlint` need no asking.
- Personal permissions go in `.claude/settings.local.json` (gitignored).
