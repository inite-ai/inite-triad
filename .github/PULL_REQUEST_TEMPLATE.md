## What this changes, in plain words

<!-- Two or three sentences a non-engineer can follow: what an operator or user will notice. -->

## Zone

<!-- See "Zones" in AGENTS.md. -->
- [ ] green
- [ ] yellow — what could change for an existing deployment:
- [ ] red — approved issue: #

Contract (`docs/compatibility.md`) changed? no / yes — rules: <!-- e.g. A-5, §9 -->
Cross-service? no / yes — linked service PRs, in the §7 / B-3 / §10 order:

## Gates

- [ ] `shellcheck bootstrap.sh verify.sh postgres/init-databases.sh .devcontainer/post-create.sh`
- [ ] `actionlint`
- [ ] `docker compose --env-file .env.example config -q`
- [ ] e2e (`up` → `bootstrap.sh` → `verify.sh`, amd64 + arm64) — runs in CI on this PR

## Checks

- [ ] new or changed `verify.sh` checks: <!-- what each would catch -->
- [ ] no existing check weakened, skipped or removed
- [ ] README updated where behaviour changed

## AI-assisted

<!-- Disclosure, not judgement. -->
- [ ] no
- [ ] yes — agent:
