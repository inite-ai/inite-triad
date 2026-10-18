# AGENTS.md — INITE Triad

Instructions for AI coding agents (Claude Code, Cursor, Codex, Copilot, Gemini
CLI, Windsurf…) working in this repo. Humans: [README](README.md) first.

## What this is

The one-compose deployment of the **INITE Triad** — Auth, Brain and Billing
run together from their released images. There is no application code here:
`compose.yaml` wires the services, `bootstrap.sh` creates the admin and OAuth
clients, `verify.sh` proves the wiring with real tokens, and
[`docs/compatibility.md`](docs/compatibility.md) is the **public, normative
token & compatibility contract** the three services implement.
Auth issues tokens; Brain and Billing verify them. Because the contract lives
here, this repo is the **entry point for any idea that spans services** — start
with the routing guide below.

## Which repo owns what (route the idea first)

| Repo | Owns | Clone |
|---|---|---|
| **Auth** — inite-auth-service | identity, sign-in (password, passkeys, magic links, MFA), organizations and roles (the `org` claim), the OAuth 2.1 / OIDC server, OAuth clients and dynamic registration, tokens and their claims, signing keys / JWKS, `ik_…` API keys, revocation (Shared Signals) | `git clone https://github.com/inite-ai/inite-auth-service` |
| **Billing** — inite-billing-service | plans, subscriptions, payments and payment rails, metered credits, entitlements, checkout, agent wallets, `x-api-key` service keys, billing's MCP (`billing:account`, `wallet:pay`) | `git clone https://github.com/inite-ai/inite-billing-service` |
| **Brain** — inite-brain-service | memory, the knowledge graph, facts, search and synthesis, MCP memory tools, `brain_…` API keys, tenant isolation, GDPR forget, ingestion sources | `git clone https://github.com/inite-ai/inite-brain-service` |
| **Triad** — this repo | how the three run together: compose wiring, bootstrap, the end-to-end checks, the token contract, the version matrix, deploy docs | — |

How to tell where an idea belongs — ask in this order:

1. Does it change **what a token says or who may get one** (a claim, a scope, an
   audience, the issuer, a signing key, a new credential kind)? → Auth **and** the
   contract here: a cross-service change (below).
2. Is it about **who someone is or how they sign in**? → Auth.
3. Is it about **money** — prices, plans, credits, limits that cost money, paying? → Billing.
4. Is it about **what an agent remembers or finds**? → Brain.
5. Is it only about **running them together** — versions, compose, bootstrap,
   checks, deploy docs? → this repo.
6. More than one answer → cross-service: file the spec here, one PR per repo.

Examples: "sign in with GitHub" → Auth only. "Charge credits per memory write"
→ Billing (charge API) + Brain (calls it with an `x-api-key`), no token change.
"A new scope `brain:export`" → Auth scope registry + Brain enforcement + contract
§6 C-2 table: cross-service, contract change. "verify.sh should check Billing's
`/mcp` discovery" → this repo only.

If the idea belongs to **one other repo**, tell the person to clone that repo
(URL above), open their agent there and run `/contribute` (Claude Code) or say
"read AGENTS.md and CONTRIBUTING.md and help me with: <idea>" — and stop here.

## Cross-service changes

The contract decides the order; never improvise it.

1. **Spec issue here** ([product idea](.github/ISSUE_TEMPLATE/product-idea.yml)):
   what changes in each repo, and whether the contract changes.
2. **Contract change = PR here** updating `docs/compatibility.md` (red zone:
   a maintainer approves the design in the issue first). Link it from every
   service PR. The service PRs also update the conformance fixtures listed in
   contract §12 in the same release train.
3. **Backward compatibility (§7):** additive within a minor (B-1). A change to
   the meaning or shape of an existing claim ships in overlap (B-2): verifiers
   accept old **and** new in release N, Auth emits the new form in N or later,
   the old form goes no earlier than N+1 minor, announced in each CHANGELOG.
   Stricter verification is opt-in for one minor first (B-4).
4. **Rule B-3 — verifiers first** for anything they must *recognise*: a new
   issuer URL, a new signing key, a new audience clients will request. Brain and
   Billing release before Auth starts emitting it. The exact issuer-migration
   and key-rotation sequences are in B-3.
5. **Upgrade order (§10):** otherwise **Auth → Brain → Billing**, one service
   at a time; roll back in reverse.
6. **After the releases:** a PR here bumps `*_VERSION` in `.env.example` and the
   README badges, and adds the combination to the §9 matrix (a maintainer
   approves the matrix edit). The e2e workflow proves the combination.

## Ground rules (non-negotiable)

1. **Never weaken a check to make CI pass** — no deleting, loosening or skipping
   a `verify.sh` check or an `e2e.yml` step/arch. Fix the cause or report it.
2. **`docs/compatibility.md` is normative**: it wins over every service doc. Its
   rules change only through an approved issue (red zone).
3. **Don't touch the §8 wiring in `compose.yaml`** (issuer, audiences, JWKS URLs,
   `RBAC_TOKEN_CLAIMS_ENABLED`, `PERSONAL_WORKSPACE_PROVISIONING_ENABLED`, the
   `auth-keys` signing key) except as part of an approved contract change.
4. **Don't start the stack on someone's machine without asking.** `docker compose
   up` pulls ~5 GB of images and uses ~5 GB of RAM; the full e2e runs in CI.
   `docker compose … config -q` only validates and is always fine.
5. **Never commit secrets**: `.env`, `.secrets/`, keys. `.env.example` holds
   localhost placeholders marked `[secret]`; keep it that way.
6. **Pin released versions** — never `latest`; bump only to tags that exist,
   in the §10 order, checked against §9.
7. **A service bug is fixed in the service repo.** A workaround here carries a
   comment naming the upstream issue (see `bootstrap.sh`, Redis in `compose.yaml`)
   and the PR proposes a §11 divergence entry.
8. `bootstrap.sh` stays **idempotent**; `verify.sh` exits non-zero on the first failure.
9. No key rotation or issuer change outside the B-3 sequence.

## Zones

| Path | What lives there | Zone |
|---|---|---|
| `docs/compatibility.md` | the normative token & compatibility contract | **red** |
| `compose.yaml` — issuer / audience / JWKS / RBAC env, `auth-keys` | contract §8 wiring | **red** |
| `verify.sh` — existing checks | the end-to-end proof of the contract | **red** to weaken; **green** to add a check |
| `bootstrap.sh` — client scopes / audiences / grants | the OAuth clients of §8.1 | **red** |
| `bootstrap.sh` — everything else | admin creation, secrets file | yellow |
| `compose.yaml` — the rest | healthchecks, volumes, ports, non-contract env | yellow |
| `postgres/init-databases.sh` | runs once, on the first boot of the volume only | yellow |
| `.github/workflows/` | `e2e.yml` (stack on amd64 + arm64), `lint.yml` | yellow (red to drop an arch or step) |
| `.env.example` | version pins and localhost defaults | green to bump a released version; yellow for new vars |
| `LICENSE` | AGPL-3.0 | red — ask a human |
| `README.md`, `AGENTS.md`, `CONTRIBUTING.md`, `docs/` other than the contract, `.devcontainer/` | docs and dev env | green |

Green: just do it. Yellow: CI green + a note in the PR on what could break for
an existing deployment. Red: stop, open an issue with the spec, wait for a
maintainer.

## Setup

- **Codespaces:** [open in one click](https://codespaces.new/inite-ai/inite-triad)
  — `.devcontainer/` gives Docker-in-Docker (so `docker compose up` works
  inside), `shellcheck`, `actionlint`, `jq`, ports 3002–3004 forwarded, and a
  `.env` copied from `.env.example`. Ask for 4 cores / 8 GB (Brain needs ~4 GB).
- **Local:** Docker with Compose v2, `curl`, `jq`, `openssl`; for the gates also
  `shellcheck` and `actionlint`. No install step — there are no dependencies.
- **Running the stack** (only if the human agreed; see ground rule 4):

  ```bash
  cp .env.example .env
  docker compose up -d --wait --wait-timeout 600
  ./bootstrap.sh
  ./verify.sh
  docker compose down -v        # wipes the volumes
  ```

## Commands

What CI runs ([lint.yml](.github/workflows/lint.yml), [e2e.yml](.github/workflows/e2e.yml)).
**Done = all of these green.**

| Gate | Command | Where |
|---|---|---|
| shell lint | `shellcheck bootstrap.sh verify.sh postgres/init-databases.sh .devcontainer/post-create.sh` | local + CI |
| workflow lint | `actionlint` | local + CI |
| compose validation | `docker compose --env-file .env.example config -q` | local + CI |
| devcontainer build | `devcontainers/ci` builds `.devcontainer/` and runs the three gates inside | CI only |
| end to end | `cp .env.example .env && docker compose up -d --wait --wait-timeout 600 && ./bootstrap.sh && ./verify.sh` | CI (amd64 + arm64) |

There is no build, unit test or formatter. `verify.sh` has no single-check mode;
it runs top to bottom.

Bumping a version after a release (green): confirm the release and the
multi-arch image, then edit `.env.example` and the README badge.

```bash
gh release list -R inite-ai/inite-brain-service -L 3     # auth/billing tags: inite-<svc>-vX.Y.Z
docker buildx imagetools inspect mikefluff/inite-brain-service:v2.4.0 | grep Platform  # needs linux/amd64 + linux/arm64
```

The image tag is always `vX.Y.Z`. A combination not yet in the §9 matrix:
say so in the PR; the e2e run is the evidence a maintainer uses to add it.

## Architecture map

- `compose.yaml` — `postgres` (pgvector; `postgres/init-databases.sh` creates one
  database and owner role each for Auth and Billing), `redis`, `surrealdb` (Brain).
- `auth-keys` — one-shot: generates Auth's RS256 key into the `auth-keys` volume
  once; restarts leave it alone.
- `auth` — migrates, then serves on 3002; `iss` = `AUTH_PUBLIC_URL`.
- `brain` (host 3004) and `billing` (host 3003) — verify Auth tokens with keys
  fetched in-network from `http://auth:3002/.well-known/jwks.json`, pinning
  the issuer `AUTH_PUBLIC_URL`.
- `bootstrap.sh` — registers the admin through Auth's API, grants the admin role
  with one SQL statement, creates the OAuth clients `brain-service`,
  `inite-billing`, `triad-quickstart`; secrets go to `.secrets/triad.env` (600).
- `verify.sh` — 1 health + issuer agreement, 2 M2M token → Brain MCP, 3 person
  token (PKCE, RFC 8707) → Brain, then refresh keeps `aud`, 4 person token →
  Billing, 5 each token refused by the other verifier.

Where to add things: a new end-to-end check → a numbered section of `verify.sh`
(+ its header comment + the README list) — it may call only endpoints the
**pinned** releases have; find them in the service repo's README / `docs/`
at that tag, not on its `main`. A new service env var → that service's
`environment:` in `compose.yaml` + `.env.example` with a comment; a new OAuth
client → `bootstrap.sh` `client …` call (red if it touches §8.1); a contract
rule → `docs/compatibility.md` (red). Features of a service go to its own repo.

## From idea to PR

Run this loop **with** the human; explain each step in plain words.

1. Restate the idea in plain words; ask at most 3 clarifying questions.
2. **Route it** (table above). Another single repo → hand off with its clone URL
   and stop. Cross-service → the process above. This repo → go on. Check for an
   existing issue: `gh issue list -R inite-ai/inite-triad --search "<words>"`.
3. Write a short spec: problem, what a user/operator sees, change to compose /
   scripts / contract, effect on existing deployments, risks, out of scope.
   **Red zone → stop**: open an issue with the spec (product-idea template) and
   wait for a maintainer.
4. Plan small steps.
5. Implement. For a new check, write it so it would fail on the bug it guards
   (say in the PR what that failure looks like).
6. Run the local gates (Commands); the e2e runs on the PR.
7. Update the README (quick start, `verify.sh checks` list, tested-on) when behaviour changes.
8. Commit with conventional commits: `feat:`, `fix:`, `docs:`, `docs(contract):`,
   `ci:`, `chore:`; `!` for breaking (e.g. a check that rejects a combination
   that passed before). No release automation here — the history is the changelog.
9. Open a PR with the [template](.github/PULL_REQUEST_TEMPLATE.md) filled,
   understandable to a non-engineer. Watch CI; do not merge.

## Conventions

- Shell: `#!/usr/bin/env bash` + `set -euo pipefail`; `postgres/init-databases.sh`
  is POSIX `sh` (it runs in the Postgres image). Must pass shellcheck; a
  `disable` carries a reason (see `verify.sh` SC2015).
- Comments say **why** and cite contract rule ids (`I-1`, `A-2`, `B-3`, `§8.1`).
- Output: `✓` passed, `✗` failed, `·` already done; `verify.sh` uses `ok` /
  `fail` and `check && ok … || fail …`.
- Read `.env` with the `envval` helper (strips inline comments); secrets from
  `.secrets/triad.env` with `secret`.
- Compose: required values as `${VAR:?set VAR in .env}`; host ports bind to
  `${BIND_ADDR:-127.0.0.1}`.
- Branches `feat/…`, `fix/…`, `docs/…`; one concern per PR.

## Testing

The test suite is `verify.sh`, run against the real released images by `e2e.yml`.
To add a check: put it in the right numbered section, reuse `status` (HTTP code),
`mcp` (JSON-RPC to Brain), `claims` (decode a JWT), `person_token` (PKCE flow);
section 5 (audience isolation) is a compact example. Every check prints `ok` on
success and calls `fail` (exit 1) otherwise — never a warning that passes.

## When to ask a human

- anything in a red zone, any edit to `docs/compatibility.md` (including §9 / §11);
- starting the stack locally;
- a version bump across a major, or one whose e2e run fails;
- which contract version to bump: §7 B-5 names `registry/compatibility.yaml`,
  which is not in this repo — the version shown here is the *Status* line of
  `docs/compatibility.md`;
- an e2e failure that looks like a service bug (it belongs upstream);
- licensing, security, or the idea doesn't fit any of the four repos.

## Help

Issues: https://github.com/inite-ai/inite-triad/issues (template: *Product idea*).
Contributing: [CONTRIBUTING.md](CONTRIBUTING.md). Security: [SECURITY.md](SECURITY.md)
— never in a public issue. Claude Code: `/contribute` runs the loop above,
`/spec-idea` only files an idea.
