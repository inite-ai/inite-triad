#!/usr/bin/env bash
# INITE Triad — first-run bootstrap. Idempotent: safe to re-run.
#
#   ./bootstrap.sh
#
# 1. Creates the first Auth administrator.
# 2. Registers the OAuth clients the Triad needs (contract §8.1):
#      brain-service     M2M → Brain   client_credentials, aud=brain, sub=<tenant>
#      inite-billing     the billing frontend, first-party, aud=inite-billing
#      triad-quickstart  a first-party user client (auth code + PKCE) that asks
#                        for Brain's RFC 8707 resource — what an MCP connector does
# 3. Writes the generated client secrets and the admin password to
#    .secrets/triad.env (chmod 600). Secrets are shown by Auth once; that file
#    is the only copy.
#
# Requires: docker compose, curl, jq. Talks to Auth at AUTH_PUBLIC_URL.
# Set COMPOSE_PROJECT_NAME if you started the stack with `-p <name>`.
#
# Why not Auth's own `npm run create-admin` / `register-*-clients`: in
# v1.12.0 they run through ts-node, which the release image does not ship,
# and construct a Prisma client without the driver adapter Prisma 7 requires
# (fixed for create-admin by inite-auth-service#241; the register-* scripts
# import src/, which is not in the image). So this script does the same thing
# through Auth's public API — register, then one SQL statement to grant the
# admin role (the only step the API cannot do before an admin exists), then
# POST /v1/admin/oauth-clients, which generates each secret server-side.
set -euo pipefail

cd "$(dirname "$0")"
[ -f .env ] || { echo "No .env — run: cp .env.example .env" >&2; exit 1; }
for bin in docker curl jq; do
  command -v "$bin" >/dev/null || { echo "$bin is required" >&2; exit 1; }
done

envval() { # the value of KEY in .env (last one wins), inline comment stripped
  sed -n "s/^$1=//p" .env | tail -1 | sed -E 's/[[:space:]]+#.*$//; s/^"(.*)"$/\1/'
}

AUTH_URL="${TRIAD_AUTH_URL:-$(envval AUTH_PUBLIC_URL)}"
BRAIN_PUBLIC_URL="$(envval BRAIN_PUBLIC_URL)"
BILLING_PUBLIC_URL="$(envval BILLING_PUBLIC_URL)"
TENANT="${TRIAD_TENANT:-co_triad}"
SECRETS=.secrets/triad.env

mkdir -p .secrets && chmod 700 .secrets
touch "$SECRETS" && chmod 600 "$SECRETS"
secret() { sed -n "s/^$1=//p" "$SECRETS" | tail -1; }
keep()   { grep -q "^$1=" "$SECRETS" || echo "$1=$2" >> "$SECRETS"; }

ADMIN_EMAIL="${ADMIN_EMAIL:-$(secret ADMIN_EMAIL)}"; ADMIN_EMAIL="${ADMIN_EMAIL:-admin@example.com}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-$(secret ADMIN_PASSWORD)}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-$(openssl rand -base64 24 | tr -d '/+=' | cut -c1-24)}"
keep ADMIN_EMAIL "$ADMIN_EMAIL"
keep ADMIN_PASSWORD "$ADMIN_PASSWORD"

echo "→ waiting for Auth at $AUTH_URL"
for i in $(seq 1 90); do
  curl -sf "$AUTH_URL/health" >/dev/null && break
  [ "$i" = 90 ] && { echo "Auth is not healthy — docker compose logs auth" >&2; exit 1; }
  sleep 2
done

issuer="$(curl -sf "$AUTH_URL/.well-known/openid-configuration" | jq -r .issuer)"
if [ "$issuer" != "$(envval AUTH_PUBLIC_URL)" ]; then
  echo "✗ discovery issuer '$issuer' ≠ AUTH_PUBLIC_URL (contract rule I-1)" >&2; exit 1
fi
echo "✓ issuer $issuer"

# ── 1. administrator ────────────────────────────────────────────────────────
body="$(jq -nc --arg e "$ADMIN_EMAIL" --arg p "$ADMIN_PASSWORD" '{email:$e,password:$p,name:"Triad Admin"}')"
code="$(curl -s -o /tmp/triad-reg.$$ -w '%{http_code}' -H 'content-type: application/json' \
  -d "$body" "$AUTH_URL/v1/auth/password/register")"
case "$code" in
  200|201) echo "✓ registered $ADMIN_EMAIL" ;;
  400) echo "· $ADMIN_EMAIL already registered" ;;
  *) echo "✗ register: HTTP $code $(cat /tmp/triad-reg.$$)" >&2; rm -f /tmp/triad-reg.$$; exit 1 ;;
esac
rm -f /tmp/triad-reg.$$

# The admin role lives in users.metadata (Auth's AdminGuard reads it per request).
docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -qtA -U postgres -d auth \
  -v email="$ADMIN_EMAIL" >/dev/null <<'SQL'
UPDATE users
   SET metadata = coalesce(metadata, '{}'::jsonb) || '{"roles":["user","admin"],"isAdmin":true}'::jsonb
 WHERE email = :'email';
SQL
echo "✓ $ADMIN_EMAIL is an Auth administrator"

login="$(jq -nc --arg e "$ADMIN_EMAIL" --arg p "$ADMIN_PASSWORD" '{email:$e,password:$p}')"
ADMIN_TOKEN="$(curl -sf -H 'content-type: application/json' -d "$login" \
  "$AUTH_URL/v1/auth/password/login" | jq -r .access_token)"
[ -n "$ADMIN_TOKEN" ] && [ "$ADMIN_TOKEN" != null ] || { echo "✗ admin login failed" >&2; exit 1; }

# ── 2. OAuth clients ────────────────────────────────────────────────────────
client() { # client <id> <json> → creates it once, stores the secret
  local id="$1" json="$2" upper res
  upper="$(echo "$id" | tr 'a-z-' 'A-Z_')_CLIENT_SECRET"
  if curl -sf -H "authorization: Bearer $ADMIN_TOKEN" "$AUTH_URL/v1/admin/oauth-clients/$id" \
       | jq -e '.clientId' >/dev/null 2>&1; then
    curl -sf -X PUT -H "authorization: Bearer $ADMIN_TOKEN" -H 'content-type: application/json' \
      -d "$(echo "$json" | jq -c 'del(.clientId)')" "$AUTH_URL/v1/admin/oauth-clients/$id" >/dev/null
    echo "· client $id exists (non-secret fields refreshed)"
    return
  fi
  res="$(curl -sf -H "authorization: Bearer $ADMIN_TOKEN" -H 'content-type: application/json' \
    -d "$json" "$AUTH_URL/v1/admin/oauth-clients")" || { echo "✗ create client $id" >&2; exit 1; }
  keep "$upper" "$(echo "$res" | jq -r .clientSecret)"
  echo "✓ client $id"
}

client brain-service "$(jq -nc --arg t "$TENANT" '{
  clientId: "brain-service", name: "INITE Brain (M2M)", redirectUris: [],
  allowedGrants: ["client_credentials"], allowedScopes: ["brain:read","brain:write"],
  allowedAudiences: ["brain"], companyId: $t }')"

client inite-billing "$(jq -nc --arg b "$BILLING_PUBLIC_URL" --arg f "${BILLING_FRONTEND_URL:-http://localhost:3001}" '{
  clientId: "inite-billing", name: "INITE Billing", firstParty: true,
  redirectUris: [($f + "/callback"), "http://127.0.0.1/callback"],
  allowedGrants: ["authorization_code","refresh_token"],
  allowedScopes: ["openid","profile","email","offline_access","billing:account"],
  allowedAudiences: ["inite-billing", ($b + "/mcp")] }')"

client triad-quickstart "$(jq -nc --arg u "$BRAIN_PUBLIC_URL" '{
  clientId: "triad-quickstart", name: "INITE Triad quick start", firstParty: true,
  redirectUris: ["http://127.0.0.1/callback"],
  allowedGrants: ["authorization_code","refresh_token"],
  allowedScopes: ["openid","profile","email","offline_access","brain:read","brain:write"],
  allowedAudiences: [$u, ($u + "/mcp")] }')"

keep TRIAD_TENANT "$TENANT"
echo
echo "Done. Admin login and client secrets: $SECRETS (chmod 600)."
echo "Next: ./verify.sh — mints real tokens and calls Brain and Billing with them."
