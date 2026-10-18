---
name: contribute
description: Use when someone says "I have an idea", "I want to add / change / fix something" in the INITE Triad, Auth, Billing or Brain, or asks where a product idea belongs. Routes the idea to the repo that owns it first; if it belongs here (deployment, compose, bootstrap, verify checks, the token contract) or spans services, runs idea → spec → plan → change → gates → PR, stopping at red zones.
---

# /contribute — INITE Triad

The person may not be an engineer. Explain what you are doing, and why, in
plain words at every step. `AGENTS.md` is the source of truth; re-read the
section a step names when unsure.

## 1. Understand

Restate the idea in two or three plain sentences. Ask at most 3 clarifying
questions, only ones whose answer changes where it goes or what gets built.

## 2. Route it — before anything else

Use AGENTS.md "Which repo owns what" and its six questions. Tell the person
the verdict and the reason in one sentence each.

- **Belongs to one other repo** (Auth: identity, sign-in, OAuth clients,
  tokens · Billing: plans, payments, credits, wallets, checkout · Brain:
  memory, knowledge, MCP memory tools). Tell them, and stop here:

  > This belongs in **<repo>**. Clone it and start there:
  > `git clone https://github.com/inite-ai/<repo>` → open your agent in
  > that folder → run `/contribute` (Claude Code), or, if that repo has no
  > `/contribute` yet, say "read AGENTS.md and CONTRIBUTING.md and help me
  > with: <the idea restated>".

  `<repo>` is exactly one of `inite-auth-service`, `inite-billing-service`,
  `inite-brain-service`. Offer to write the restated idea down for them to
  paste.

- **Spans services** (or changes a claim, scope, audience, issuer, key or
  credential kind): this repo is the right start, but the work is a spec
  issue first. Go to step 3, then **stop at step 4** — file the issue with
  the per-repo breakdown and the order from AGENTS.md "Cross-service changes"
  (§7, B-3 verifiers first, §10 Auth → Brain → Billing). Code happens in the
  service repos after a maintainer approves.

- **Belongs here** (compose, bootstrap, verify checks, versions, deploy
  docs, the contract): go on.

- **Fits none of the four**: say so, and offer to file a product-idea issue
  here for the maintainers to route.

Check for an existing issue:
`gh issue list -R inite-ai/inite-triad --search "<key words>" --state all`.
If one exists, show it and ask whether to build on it.

## 3. Spec

Write a short spec and show it: problem · what an operator/user will see ·
changes (compose / bootstrap / verify / docs / contract) · effect on an
existing deployment (a re-run `bootstrap.sh`, an existing Postgres volume —
`postgres/init-databases.sh` never re-runs) · risks · out of scope.

## 4. Zone check — STOP on red

Look up every path the spec touches in AGENTS.md "Zones". Red if it touches
`docs/compatibility.md`, the §8 wiring in `compose.yaml` (issuer, audiences,
JWKS URLs, RBAC/personal-workspace flags, `auth-keys`), the OAuth client
scopes/audiences in `bootstrap.sh`, weakening any `verify.sh` check or e2e
step, or `LICENSE`.

Red, or cross-service → do not write code. File the spec as an issue:

```bash
gh issue create -R inite-ai/inite-triad --label idea \
  --title "<short title>" --body-file <spec file>
```

(body headings: *What do you want to be possible?*, *Who is it for / why*,
*How would you know it works?*, *Which parts does it touch?*, *Spec*). No
`gh`? Give them https://github.com/inite-ai/inite-triad/issues/new?template=product-idea.yml
and the text to paste. Tell them a maintainer must approve the design; stop.

## 5. Plan and build (green / yellow only)

Work on a branch (`feat/…`, `fix/…`, `docs/…`). Small steps; say what each
does. For a new `verify.sh` check, reuse `status` / `mcp` / `claims` /
`person_token`, print with `ok`, exit with `fail`, and update the header
comment and the README "verify.sh checks" list. Never loosen an existing check.

## 6. Gates

Run, and show the result in plain words:

```bash
shellcheck bootstrap.sh verify.sh postgres/init-databases.sh .devcontainer/post-create.sh
actionlint
docker compose --env-file .env.example config -q
```

Do **not** run `docker compose up` unless the person explicitly agrees (it
needs ~5 GB of RAM); the full end-to-end run (amd64 + arm64) happens in CI on
the PR.

## 7. Commit and PR

Conventional commit (`feat:` / `fix:` / `docs:` / `ci:`; `!` if an existing
deployment or version combination would now fail). Open the PR with
`.github/PULL_REQUEST_TEMPLATE.md` filled — zone, gates run, checks added,
AI-assisted. Watch `gh pr checks --watch`; if e2e fails, read the "Logs on
failure" step and explain the cause; never weaken a check to get green. Do
not merge — a maintainer does.
