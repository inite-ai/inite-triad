# INITE Triad — token & compatibility contract

> **Status:** normative, contract version **1.0.0**.

The INITE Triad is the three horizontal services every project on the
platform authenticates and bills through:

| Role | Service | Repo | What it does with tokens |
|---|---|---|---|
| **Issuer** | `inite.service.auth` | `inite-auth-service` | OAuth 2.1 / OIDC authorization server. Mints every access token, publishes the JWKS. |
| **Verifier** | `inite.service.billing` | `inite-billing-service` | Resource server. Verifies person/agent tokens; product backends call it with `x-api-key`. |
| **Verifier** | `inite.service.brain` | `inite-brain-service` | Resource server (REST + MCP). Verifies person and M2M tokens; maps them to a tenant. |

This document is the single place the three agree on. Where a service's own
README, `.env.example` or docs disagree with it, **this document wins** and
the service doc is a bug. The key words MUST, MUST NOT, SHOULD, MAY are used
as in RFC 2119.

Every rule below was checked against the code of each service; the
evidence and the divergences found while writing it are in
[§11](#11-divergence-register).

---

## 1. Signing, keys and discovery

- **T-1.** Auth MUST sign access tokens and id_tokens with **RS256** and put
  the signing key's `kid` in the JWS header (`JWT_ACTIVE_KID`, default
  `auth-rs256-key-1`). HS256 (`JWT_SECRET`) is development-only; Auth refuses
  to boot in production without `JWT_PRIVATE_KEY`.
- **T-2.** Auth MUST publish every key that may still verify a live token at
  `<JWT_ISSUER>/.well-known/jwks.json` (active key plus
  `JWT_PUBLIC_KEY_NEXT` / `JWT_PUBLIC_KEY_PREV` during a rotation).
- **T-3.** Verifiers MUST pin the accepted algorithms to `RS256` (billing:
  hard-coded; brain: `AUTH_SERVICE_JWT_ALGS`, default `RS256`) and MUST NOT
  accept `alg: none` or a symmetric algorithm in production.
- **T-4.** Verifiers MUST fetch keys from Auth's JWKS by `kid` and MUST
  re-fetch on an unknown `kid` (both do: billing via `jwks-rsa`, 10 min cache,
  10 req/min; brain via `jose.createRemoteJWKSet`).
- **T-5.** The JWKS URL is configured, not discovered: billing derives it as
  `${AUTH_SERVICE_URL}/.well-known/jwks.json`; brain takes the full URL in
  `AUTH_SERVICE_JWKS_URL`. Both MUST point at the same Auth deployment that
  signs the tokens.

## 2. `iss` — issuer

- **I-1.** Auth signs `iss` = `JWT_ISSUER`, verbatim. Discovery
  (`/.well-known/openid-configuration`, `/.well-known/oauth-authorization-server`)
  advertises `issuer` = `OIDC_ISSUER`. **`JWT_ISSUER` and `OIDC_ISSUER` MUST
  be the same string** (RFC 8414 §3.3); Auth logs a boot warning when they
  differ.
- **I-2.** The issuer is a URL with **no trailing slash** (`https://auth-api.example.com`).
  It is not necessarily the host the JWKS is fetched from: INITE's own
  deployment signs `iss = https://auth-api.inite.ai` and serves keys at
  `https://auth.inite.ai/.well-known/jwks.json` too. Pin the value **in the
  token**, never the JWKS host.
- **I-3.** Every verifier MUST validate `iss`, and MUST refuse to start in
  production without a configured issuer (billing `JWT_ISSUER`, brain
  `AUTH_SERVICE_ISSUER`).
- **I-4.** The configured issuer MAY be a **comma-separated list**, used only
  during an issuer migration ([§7](#7-backward-compatibility-policy)). A
  trailing slash on the configured value or in the token MUST NOT make a
  difference. The first entry is the deployment's issuer (billing uses it for
  discovery and for recognising an agent's `did:web`).

## 3. `aud` — audience (RFC 8707)

- **A-1.** Auth puts exactly one string in `aud` on every OAuth access token
  (issued by `/token` or the device and token-exchange grants):
  - the RFC 8707 `resource` the client named — authorization code (`/authorize?resource=`),
    device flow (`/device_authorization?resource=`), token exchange
    (`resource=` or `audience=`), and `client_credentials` (`audience=`, or
    `resource=` when `audience` is absent and the client may have it);
  - otherwise, for `client_credentials`/token exchange, the client's first
    `allowedAudiences` entry; otherwise the client's `client_id`.
- **A-2.** A refresh-token rotation MUST keep the audience the original grant
  was bound to (Auth persists `RefreshToken.resource`; auth #217). A verifier
  MAY rely on a refreshed token having the same `aud` as the first one.
- **A-3.** If the client has a non-empty `allowedAudiences`, an explicitly
  requested audience outside it is refused (`400`). A `resource=` outside it
  on `client_credentials` is ignored (backward compatible, see [§7](#7-backward-compatibility-policy)).
- **A-4.** The id_token's `aud` is always the `client_id` (OIDC Core). An
  id_token MUST NOT be accepted as an access token; the audience rules below
  reject it everywhere except a first-party client whose id is a billing
  audience — never send id_tokens to a resource server.
- **A-5. Brain** MUST accept, and only accept, `aud` ∈
  - `AUTH_SERVICE_AUDIENCE` (the vertical name, default `brain`) — operator
    keys and `audience=brain` M2M grants;
  - `BRAIN_PUBLIC_URL` and `<BRAIN_PUBLIC_URL>/mcp` — what MCP connectors get;
  - `<BRAIN_PUBLIC_URL>/mcp/<companyId>` — the per-tenant RFC 9728 resource —
    **only when `<companyId>` is the tenant the token itself resolves to**;
  - or exactly `AUTH_SERVICE_AUDIENCES` (comma-separated) when set, which
    replaces the first two bullets.
  The JWKS path and RFC 7662 introspection (`ik_…` keys) MUST use the same set.
- **A-6. Billing** accepts, when `JWT_AUDIENCE` is set, `aud` ∈ `JWT_AUDIENCE`
  (comma-separated; the frontend client id, `inite-billing`) ∪ billing's own
  resources `<FRONTEND_URL>/mcp`, `<FRONTEND_URL>/mcp/wallet`,
  `<FRONTEND_URL>/v1/agent-wallet`. Independently of `JWT_AUDIENCE`, the MCP
  endpoint refuses any token whose `aud` is another `https://` resource, and
  the wallet endpoints require their own resource in `aud`.
  `JWT_AUDIENCE` SHOULD be set in production today (billing warns at boot when
  it is not) and becomes a MUST in the next billing minor.
- **A-7.** A client that wants one token for several services MUST NOT get
  one: tokens are single-audience. Ask Auth once per resource.

## 4. `sub` — subject

- **S-1.** `sub` is a **DID**, never a UUID and never an email:
  | Token | `sub` |
  |---|---|
  | person, any user flow | the person's `did:key:…` (`User.did`) |
  | token exchange | the subject token's `sub` (unchanged) |
  | agent on its own (`client_credentials`, self-registered `dcr_` client) | `did:web:<issuer host>[:port]:agents:<client_id>` |
  | other `client_credentials` | the client's `companyId`, else its `client_id` |
  | `ik_…` key, introspected | the owning user's DID, else the organization's `companyId` |
- **S-2.** Verifiers MUST store and compare `sub` as an opaque string up to
  200 characters, `:` included. Database columns and DTOs that hold a
  customer / user id MUST NOT be typed or validated as UUID (billing #226).
- **S-3.** The access token also carries `userId` (Auth's internal user UUID).
  It is informational; verifiers MUST NOT key data on it — key on `sub`.
- **S-4.** Who acts for the subject is `act` (RFC 8693: `act.sub`, and
  `act.client_id` when present), else `client_id` (RFC 9068). Verifiers
  attribute agent actions to that, and the data to `sub`.

## 5. `org` / `org_id` — tenant

- **O-1.** Auth adds `org` (the organization's `companyId`, e.g. `co_acme` or
  a personal workspace `co_u_<16 hex>`) and `org_id` (its UUID) **only when
  `RBAC_TOKEN_CLAIMS_ENABLED` is on**. The org is the membership matching the
  client's `companyId`, else the user's first membership; with
  `PERSONAL_WORKSPACE_PROVISIONING_ENABLED` a user with none gets one on the
  first request for a provisioning vertical's scopes (`brain:*`).
  `client_credentials` tokens never carry `org`; token exchange copies `org`,
  `org_id` and `roles` from the subject token.
- **O-2.** `companyId` values are `^[A-Za-z0-9_-]{1,64}$` (brain uses it as a
  database name).
- **O-3. Brain** tenant mapping (JWKS and introspection alike):
  `org` present → tenant = `org`, end-user = `sub`;
  `org` absent → tenant = `sub` (M2M), no end-user — and a `sub` outside the
  `companyId` charset (every DID) is **rejected**, never used as a tenant.
  The tenant-less `POST /mcp` takes the tenant from this mapping;
  `POST /mcp/<companyId>` MUST match it (refused otherwise).
  ⇒ **For person tokens to reach brain, Auth MUST run with
  `RBAC_TOKEN_CLAIMS_ENABLED=true`** (and SHOULD with personal workspaces).
- **O-4. Billing** is person-scoped, not tenant-scoped: it ignores `org`.
  Product backends identify themselves with a billing service key
  (`x-api-key`), not with an Auth M2M token.

## 6. Scopes, lifetimes and credentials

- **C-1.** User-flow tokens carry `scope` (space-delimited). `client_credentials`
  and token-exchange tokens carry both `scope` and `scopes` (array).
  Verifiers MUST accept either (brain prefers `scopes`, billing reads `scope`,
  which both shapes have).
- **C-2.** Scope vocabulary (Auth `src/oauth/oauth-scopes.registry.ts` is the
  source; resource servers enforce):
  | Scope | Audience | Self-registered (DCR) client may ask |
  |---|---|---|
  | `openid profile email offline_access` | Auth | yes |
  | `brain:read`, `brain:write` | brain | yes |
  | `brain:admin`, `brain:read_pii` | brain | no (operator-provisioned) |
  | `registry:publish`, `indexer:write` | brain (`ik_…` keys / M2M only) | no |
  | `billing:account` | billing `/mcp` | yes |
  | `wallet:pay` | billing `/mcp/wallet` | yes |
  Brain additionally knows `registry:curate`, `brain:read_media` and
  `brain:platform_admin`; they are never minted by Auth tokens (env/operator
  keys only). A verifier MUST drop scopes it does not know rather than fail.
- **C-3.** Lifetimes of OAuth tokens: user access tokens `JWT_ACCESS_TOKEN_EXPIRY` (default
  10 min), M2M / exchange `JWT_M2M_ACCESS_TOKEN_EXPIRY` (default 5 min),
  refresh tokens 7 days, rotated on every use; a replayed refresh token
  revokes its family and answers `400 invalid_grant` (auth #228).
- **C-3a. Auth's own session token is not an access token.** The token
  Auth's password/passkey login returns (`/v1/auth/password/login` and
  siblings) carries no `aud` and lives 1 h; it authenticates the person to
  Auth's own UI and APIs only. Verifiers MUST refuse it — the `aud` check
  already does — and clients MUST NOT send it to Brain or Billing; they get
  an OAuth token for that resource instead.
- **C-4. Clock skew.** Auth emits `iat` and `exp`, no `nbf`. Verifiers MUST
  check `exp` and MUST NOT reject a token for an `iat` slightly in the future.
  Hosts MUST run NTP; no extra skew allowance is configured (0 s on both
  verifiers), which is safe because nothing but `exp` is time-checked.
- **C-5. Revocation.** Between expiries, revocation reaches verifiers through
  Auth's Shared Signals (CAEP) stream; brain polls it (`AUTH_SSF_POLL_URL`).
- **C-6. Credential kinds** — never interchangeable:
  | Credential | Issued by | Accepted by | How verified |
  |---|---|---|---|
  | Access token (JWT) | Auth | billing, brain | JWKS, rules above |
  | `ik_…` API key | Auth admin (per org, one audience) | brain | RFC 7662 introspection, same `aud` set |
  | `brain_…` API key | brain `/v1/keys` | brain | brain's own store |
  | `x-api-key` service key | billing admin | billing | billing's own `Service` table |

## 7. Backward-compatibility policy

- **B-1. Additive only within a minor.** Auth MAY add claims, scopes or
  grant options in a minor release. Verifiers MUST ignore claims they do not
  know (both do).
- **B-2. One minor of overlap.** Any change to the *meaning or shape* of an
  existing claim — a new `iss`, a new `aud` form, a new `sub` form, moving a
  claim — ships as: verifiers accept old **and** new in release N; Auth starts
  emitting the new form in release N (or later); the old form stops being
  accepted no earlier than N+1 minor, and only after the CHANGELOG of each
  service says so.
- **B-3. Verifiers first for anything they must *recognise*:** a new issuer
  URL, a new signing key, a new audience a client will start requesting.
  Concretely, an issuer migration is: add the new issuer to
  `JWT_ISSUER` / `AUTH_SERVICE_ISSUER` lists → switch Auth's
  `JWT_ISSUER` + `OIDC_ISSUER` → wait one access+refresh lifetime → remove
  the old one. A key rotation is: publish the next key
  (`JWT_PUBLIC_KEY_NEXT`) → wait ≥ the verifier JWKS cache (10 min) →
  switch `JWT_ACTIVE_KID` → keep the old key published until its tokens
  expire.
- **B-4. Stricter verification is opt-in for one minor**, then default
  (billing `JWT_AUDIENCE`: warn now, required next minor).
- **B-5.** The contract version on this document's *Status* line is bumped
  MINOR for an additive rule, MAJOR for a rule that rejects tokens that were
  accepted before.

## 8. Self-hosted deployment

### 8.1 One issuer, one audience set per service

Example: Auth at `https://auth.example.com`, Billing at
`https://billing.example.com`, Brain at `https://brain.example.com`.

**Auth**

```env
JWT_ISSUER=https://auth.example.com          # the iss in every token
OIDC_ISSUER=https://auth.example.com         # MUST equal JWT_ISSUER
JWT_PRIVATE_KEY=<RSA PKCS#8 PEM>             # required in production
JWT_PUBLIC_KEY=<RSA public PEM>
JWT_ACTIVE_KID=auth-rs256-key-1
RBAC_TOKEN_CLAIMS_ENABLED=true                # brain needs org
PERSONAL_WORKSPACE_PROVISIONING_ENABLED=true  # new users get a tenant
# (both are also Admin → Settings toggles; a value set there overrides env)
```

OAuth clients: the billing frontend is client `inite-billing` (first-party,
`aud = inite-billing`). M2M clients that call brain get
`allowedAudiences: ["brain"]` and `allowedScopes` from §6.

**Billing**

```env
AUTH_SERVICE_URL=https://auth.example.com    # JWKS = <this>/.well-known/jwks.json
JWT_ISSUER=https://auth.example.com          # = Auth JWT_ISSUER
JWT_AUDIENCE=inite-billing                   # + /mcp, /mcp/wallet, /v1/agent-wallet implied
FRONTEND_URL=https://billing.example.com     # base of billing's OAuth resources
# JWT_SECRET only for local dev (NODE_ENV != production)
```

**Brain**

```env
AUTH_SERVICE_URL=https://auth.example.com
AUTH_SERVICE_JWKS_URL=https://auth.example.com/.well-known/jwks.json
AUTH_SERVICE_ISSUER=https://auth.example.com # = Auth JWT_ISSUER
AUTH_SERVICE_AUDIENCE=brain
BRAIN_PUBLIC_URL=https://brain.example.com   # adds <url>, <url>/mcp, <url>/mcp/<companyId>
# optional: AUTH_SERVICE_INTROSPECTION_CLIENT_ID / _SECRET for ik_… keys,
#           AUTH_SSF_POLL_URL for CAEP revocation
```

A ready-made stack wired exactly this way — one compose file, the official
images, Postgres/Redis/SurrealDB, a bootstrap for the admin and OAuth
clients, and an end-to-end check — is [inite-ai/inite-triad](https://github.com/inite-ai/inite-triad),
whose CI runs it on native amd64 and arm64.

### 8.2 Checks after deploy

1. `curl https://auth.example.com/.well-known/openid-configuration | jq .issuer`
   equals `JWT_ISSUER` and the value configured on billing and brain.
2. Billing boot log: `Pinning JWT issuer: …` and `Pinning JWT audience: …`.
3. Brain boot log: `[JwksService] JWKS verifier enabled — … audiences=[brain,<url>,<url>/mcp], issuer=…`.
4. `curl https://brain.example.com/.well-known/oauth-protected-resource | jq .authorization_servers`
   names the issuer.

## 9. Version compatibility matrix

Released tags: the last ones before the contract, and the first releases that
implement it. ✅ works, ⚠️ works with the stated limitation, ❌ broken.

| Auth ↓ / verifier → | billing `v1.3.0` | billing `v1.4.0` | brain `v2.3.0` | brain `v2.4.0` |
|---|---|---|---|---|
| **`inite-auth-service-v1.11.2`** | ⚠️ ¹ ² | ⚠️ ¹ | ⚠️ ³ | ⚠️ ³ |
| **`inite-auth-service-v1.12.0`** | ⚠️ ² | ✅ | ✅ ⁴ | ✅ ⁵ |

1. Auth 1.11.2 does not know `billing:account` / `wallet:pay` and has no
   agent (`act`, `did:web`) support, so billing's MCP and wallet surfaces
   cannot get tokens; first-party sign-in works.
2. Billing 1.3.0 validates customer ids in admin grant/adjust/charge DTOs as
   UUID, so DID users (every OAuth user) are refused there (fixed by billing #226);
   it has no `/mcp` OAuth discovery (billing #225).
3. Auth 1.11.2 drops the RFC 8707 audience on refresh: an MCP connector's
   token is accepted by brain until its first refresh (≤ 10 min), then
   `aud = <client_id>` and brain refuses it. M2M (`audience=brain`) is
   unaffected. Fixed in auth v1.12.0 (#217). It also has no personal-workspace
   provisioning (#194), so a user with no organization gets no `org`.
4. Brain 2.3.0 does not accept `aud = <url>/mcp/<companyId>` (only clients
   that build the per-tenant RFC 9728 URL themselves request it) and its
   `/mcp` 401 points at the deployment-wide metadata document.
5. Auth 1.12.0 + billing 1.4.0 + brain 2.4.0 is the combination
   [inite-triad](https://github.com/inite-ai/inite-triad) pins, and its
   `verify.sh` checks it end to end against the running images (amd64 and
   arm64, in CI): M2M and person tokens on brain, a refresh
   that keeps its audience, a person token on billing, and each token refused
   by the other verifier.

**Minimum versions for the platform contract (§1–§6): auth `v1.12.0`,
billing `v1.4.0`, brain `v2.4.0`.** Later releases stay compatible with
them under the backward-compatibility policy (§7).

## 10. Upgrade order

**Auth → Brain → Billing** (brain and billing are independent of each other;
the order between them is a convention, not a dependency).

Why Auth first — checked against the code, not assumed:

- Everything auth v1.12.0 started emitting is either additive or something
  released verifiers already tolerate: `act` and `client_id` are optional
  claims both verifiers read when present and ignore otherwise; a refreshed
  token keeping its RFC 8707 `aud` only turns a rejection into an
  acceptance; new scopes are dropped by verifiers that do not know them;
  personal-workspace `org` values (`co_u_<hex>`) fit brain's `companyId`
  charset; an agent's `did:web` `sub` reaches only billing's agent wallet.
- `client_credentials` with `resource=` now yields `aud = resource`
  instead of the client default — only when the client is allowed that
  audience, so no request that succeeded before now fails.
- The verifier upgrades widen what they accept (issuer lists, per-tenant
  audience, billing resources under a pinned audience). Nothing they start
  rejecting is something auth emits.

Exceptions — **verifiers first** (rule B-3): a new issuer URL, a signing-key
rotation, or a new audience form clients will request. Database migrations
are per service and independent; there is no cross-service schema.

Per service: run the migrations shipped with the release, deploy, then check
§8.2. Roll back in the reverse order.

## 11. Divergence register

Found while writing this contract (origin/main, 2026-10-16). Status `fixed`
links the change; `doc` = documentation corrected; `kept` = intentionally
unchanged (reason given).

| # | Where | Divergence | Status |
|---|---|---|---|
| D-1 | auth `src/oauth/token-grant.service.ts:209` | `client_credentials` read only `audience`; an RFC 8707 `resource=` was silently ignored → `aud = client_id` → refused by billing/brain | fixed — auth #231 |
| D-2 | auth `src/common/health.controller.ts:151` vs `src/oauth/oauth-token-issuer.service.ts:128` | discovery `issuer` = `OIDC_ISSUER`, token `iss` = `JWT_ISSUER`; nothing tied them together | fixed: boot warning (auth #231) + rule I-1 |
| D-3 | auth `frontend/app/docs/self-hosting/page.mdx:30` | says `OIDC_ISSUER` "goes into every signed token" (it is `JWT_ISSUER`); `JWT_ISSUER` missing from the table | doc — auth #231 |
| D-4 | auth `frontend/app/docs/self-hosting/page.mdx:28` | "RS256 / ES256 / EdDSA preferred" — only RS256 is signed | doc — auth #231 |
| D-5 | auth `frontend/app/docs/oidc/page.mdx:72-80` | claim list omits `org`/`org_id` (and their flag), `client_id`, `scope`, `aud` semantics | doc — auth #231 |
| D-6 | auth `.env.example:42` vs `deploy/docker-compose.prod.yml:84` | example issuer `https://auth.inite.ai`, production signs `https://auth-api.inite.ai` | doc — auth #231; rule I-2 |
| D-7 | brain `src/auth/protected-resource.controller.ts:57` vs `src/auth/jwks.service.ts:143` | brain advertises `<url>/mcp/<companyId>` as an RFC 9728 resource but refused it as `aud` | fixed — brain #741, tenant-bound |
| D-8 | brain `src/auth/introspection.client.ts:92` vs `jwks.service.ts` | introspection accepted only `AUTH_SERVICE_AUDIENCE`; JWKS path accepted the full list / `AUTH_SERVICE_AUDIENCES` | fixed — brain #741 |
| D-9 | brain `src/auth/jwks.service.ts:67`, billing `src/auth/strategies/jwt.strategy.ts:43` | single exact issuer: no migration window, trailing slash = lock-out | fixed — brain #741, billing #229; rule I-4 |
| D-10 | brain `src/auth/jwks.service.ts:27` | comment: "`sub` claim is the companyId" (only for M2M) | fixed — brain #741 |
| D-11 | brain `docs/operator-playbook.md:91` | "JWTs whose `scopes` claim…" — user tokens carry `scope` | doc — brain #741 |
| D-12 | billing `src/auth/strategies/jwt.strategy.ts:57`, `env.example:18` | claims Auth "does not put an `aud` claim on user access tokens" — it always does | fixed — billing #229 (comments, env.example) |
| D-13 | billing `src/auth/strategies/jwt.strategy.ts:62` | `JWT_AUDIENCE` single value: pinning it to `inite-billing` locks out every `/mcp`, `/mcp/wallet`, `/v1/agent-wallet` token | fixed — billing #229: own resources always in the set |
| D-14 | billing `src/auth/strategies/jwt.strategy.ts:9` | `sub` typed/commented as "inite_user_id (uuid)"; it is a DID (DTOs fixed in #226) | fixed — billing #229 |
| D-15 | billing `env.example:11`, `docs/getting-started.md:72` | documents `JWT_PUBLIC_KEY`; the code never reads it (JWKS or `JWT_SECRET` only) | doc — billing #229 |
| D-16 | internal ecosystem doc `04-identity.md:136` | "every JWT embeds `sessionVersion`" — no Auth token carries it | doc (here) |
| D-17 | internal ecosystem doc `04-identity.md:119` | API keys "separate from auth-service" — Auth also issues `ik_…` keys, introspected by brain | doc (here) |
| D-18 | billing `src/auth/strategies/jwt.strategy.ts` (no `org` handling) | an M2M token reaching billing would be read as a person (`sub = companyId`) | kept: billing's machine callers use `x-api-key` (O-4); no Auth client is provisioned with a billing audience for M2M |
| D-19 | both verifiers | no clock-skew allowance | kept: only `exp` is time-checked (C-4) |
| D-20 | §8.1 (this doc) | said the RBAC / personal-workspace flags are Admin → Settings only; Auth reads them DB override → env (`src/common/settings/settings.service.ts:24`) | doc (here) |
| D-21 | auth `scripts/*.ts` (`create-admin-user.ts:5` …), `package.json` `create-admin` | `new PrismaClient()` without the driver adapter Prisma 7 requires — every operator script throws; `create-admin` ran through ts-node, which the image prunes | fixed — auth #241; inite-triad's `bootstrap.sh` uses the admin API meanwhile |
| D-22 | billing `src/app.module.ts:51` | BullMQ connection built from REDIS_URL host+port only: a password-protected Redis breaks every queue | fixed — billing #240; inite-triad runs Redis without a password, network-internal |
| D-23 | auth `src/auth/auth.service.ts:302` | the password/passkey login token (`/v1/auth/password/login`) has no `aud` and a fixed 1 h TTL, against A-1 / C-3 | resolved in the contract — A-1/C-3 now name OAuth tokens and C-3a makes the session token Auth-only; both verifiers refuse it, and inite-triad's `verify.sh` checks that |

## 12. Conformance tests

Each verifier repo carries a test that mints tokens shaped exactly as Auth's
issuer code mints them (copied claim shapes, RS256 with `kid`, served by a
stub JWKS) and asserts the tenant / user / scope mapping and the rejections:

- billing: `test/triad-token-contract.spec.ts`
- brain: `test/triad-token-contract.socket-spec.ts`
- auth (issuer side): `src/oauth/__tests__/client-credentials-resource.spec.ts`,
  `refresh-keeps-audience.spec.ts`

A change to Auth's claim shapes MUST update those fixtures in the same
release train, following §7.
