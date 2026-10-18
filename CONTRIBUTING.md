# Contributing to the INITE Triad

This repo runs Auth, Brain and Billing together and holds their token &
compatibility contract ([docs/compatibility.md](docs/compatibility.md)).
Features of a single service belong in that service's repo; this one is
for how they run together, the end-to-end checks, and ideas that span
services.

**[AGENTS.md](AGENTS.md) is the source of truth** — for people and AI agents
alike: which repo owns what, the cross-service change process, zones, the
exact gates CI runs, and conventions. In short:

1. Route the idea (AGENTS.md → *Which repo owns what*). Single-service →
   that repo.
2. Red zones (the contract, the §8 wiring in `compose.yaml`, OAuth client
   scopes/audiences in `bootstrap.sh`, weakening any `verify.sh` check) start
   as an issue with a spec — use the *Product idea* template — and wait for
   a maintainer.
3. Otherwise: a branch, a small change, the local gates
   (`shellcheck`, `actionlint`, `docker compose --env-file .env.example config -q`),
   a conventional-commit message, and a PR from the template. The end-to-end
   run (amd64 + arm64) happens in CI.

With an AI agent: open the repo in Claude Code and run `/contribute` (or
`/spec-idea` to only file an idea), or tell any agent "read AGENTS.md and
help me with: …".

Security issues: [SECURITY.md](SECURITY.md), never a public issue.
By contributing you agree your work is licensed under AGPL-3.0 ([LICENSE](LICENSE)).
