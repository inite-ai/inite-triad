#!/usr/bin/env bash
# INITE Triad — end-to-end check: real tokens from Auth, used on Brain and Billing.
#
#   ./verify.sh        (after ./bootstrap.sh)
#
#  1. health / readiness of all three, and the issuer every party agrees on
#  2. M2M:    client_credentials (aud=brain)            → Brain MCP tools/list
#  3. person: auth code + PKCE, resource=<brain>/mcp     → Brain MCP (tenant = org claim),
#             then a refresh: the new token keeps its audience and still works (A-2)
#  4. person: auth code + PKCE, client inite-billing     → Billing /v1/credits/me
#  5. audience isolation: each token is refused by the other verifier (A-7)
#
# Exits non-zero on the first failure.
# ok() always succeeds, so `check && ok … || fail …` is a real if/else here.
# shellcheck disable=SC2015
set -euo pipefail
cd "$(dirname "$0")"
[ -f .secrets/triad.env ] || { echo "Run ./bootstrap.sh first" >&2; exit 1; }

envval() { sed -n "s/^$1=//p" .env | tail -1 | sed -E 's/[[:space:]]+#.*$//; s/^"(.*)"$/\1/'; }
secret() { sed -n "s/^$1=//p" .secrets/triad.env | tail -1; }

ISSUER="$(envval AUTH_PUBLIC_URL)"
AUTH="${TRIAD_AUTH_URL:-$ISSUER}"
BRAIN="${TRIAD_BRAIN_URL:-$(envval BRAIN_PUBLIC_URL)}"
BRAIN_PUBLIC="$(envval BRAIN_PUBLIC_URL)"
BILLING="${TRIAD_BILLING_URL:-$(envval BILLING_PUBLIC_URL)}"

ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }
claims() { # decode a JWT payload
  local p; p="$(echo "$1" | cut -d. -f2 | tr '_-' '/+')"
  while [ $(( ${#p} % 4 )) -ne 0 ]; do p="$p="; done
  echo "$p" | base64 -d 2>/dev/null
}
status() { curl -s -o /dev/null -w '%{http_code}' "$@"; }

echo "1. health"
for u in "$AUTH/health" "$AUTH/ready" "$BRAIN/health" "$BRAIN/ready" "$BRAIN/mcp/health" \
         "$BILLING/health" "$BILLING/health/ready"; do
  # Readiness can trail liveness by a few seconds after `up` (Brain warms its
  # scoped pool and embedder), so give each endpoint up to a minute.
  for _ in $(seq 1 30); do c="$(status "$u")"; [ "$c" = 200 ] && break; sleep 2; done
  [ "$c" = 200 ] && ok "$u" || fail "$u → HTTP $c"
done
d="$(curl -sf "$AUTH/.well-known/openid-configuration" | jq -r .issuer)"
[ "$d" = "$ISSUER" ] && ok "Auth discovery issuer = $d" || fail "discovery issuer $d ≠ $ISSUER"
prm="$(curl -sf "$BRAIN/.well-known/oauth-protected-resource" | jq -r '.authorization_servers[0]')"
[ "$prm" = "$ISSUER" ] && ok "Brain RFC 9728 authorization_servers = $prm" || fail "Brain advertises $prm"
c="$(status -X POST "$BRAIN/mcp")"
[ "$c" = 401 ] && ok "Brain /mcp without a token → 401" || fail "Brain /mcp without a token → $c"

mcp() { # mcp <token> <json-rpc body> → result JSON (SSE or JSON response)
  curl -sf -X POST "$BRAIN/mcp" -H "authorization: Bearer $1" \
    -H 'content-type: application/json' -H 'accept: application/json, text/event-stream' \
    -d "$2" | awk '!f && /^data: /{sub(/^data: /,""); print; f=1} !f && /^\{/{print; f=1}'
}

echo "2. M2M token (client_credentials) → Brain"
# Auth's token endpoint takes client_secret_post (discovery lists no _basic).
M2M="$(curl -sf -d client_id=brain-service -d "client_secret=$(secret BRAIN_SERVICE_CLIENT_SECRET)" \
  -d grant_type=client_credentials -d audience=brain -d scope='brain:read brain:write' \
  "$AUTH/v1/oauth/token" | jq -r .access_token)"
[ -n "$M2M" ] && [ "$M2M" != null ] || fail "no M2M token"
ok "token: $(claims "$M2M" | jq -c '{iss,aud,sub,scope}')"
tools="$(mcp "$M2M" '{"jsonrpc":"2.0","id":1,"method":"tools/list"}')"
n="$(echo "$tools" | jq '.result.tools | length')"
[ "${n:-0}" -gt 0 ] && ok "Brain tools/list: $n tools" || fail "tools/list: $tools"
ws="$(mcp "$M2M" '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"workspace_status","arguments":{}}}')"
echo "$ws" | jq -e '.result' >/dev/null && ok "Brain workspace_status: $(echo "$ws" | jq -r '.result.content[0].text' | jq -c '{companyId, name}' 2>/dev/null || echo ok)" \
  || fail "workspace_status: $ws"

# A person token: sign in, ask for a code (first-party clients skip consent),
# redeem it with PKCE. Same flow an MCP connector runs, minus the browser.
SESSION="$(curl -sf -H 'content-type: application/json' \
  -d "$(jq -nc --arg e "$(secret ADMIN_EMAIL)" --arg p "$(secret ADMIN_PASSWORD)" '{email:$e,password:$p}')" \
  "$AUTH/v1/auth/password/login" | jq -r .access_token)"
person_token() { # person_token <client> <secret> <scope> [resource] → token response JSON
  local verifier challenge code body
  verifier="$(openssl rand -base64 48 | tr -d '/+=\n' | cut -c1-64)"
  challenge="$(printf '%s' "$verifier" | openssl dgst -binary -sha256 | openssl base64 -A | tr '+/' '-_' | tr -d '=')"
  body="$(jq -nc --arg c "$1" --arg s "$3" --arg ch "$challenge" --arg r "${4:-}" \
    '{clientId:$c, redirectUri:"http://127.0.0.1/callback", scope:$s,
      codeChallenge:$ch, codeChallengeMethod:"S256"} + (if $r == "" then {} else {resource:$r} end)')"
  code="$(curl -sf -H "authorization: Bearer $SESSION" -H 'content-type: application/json' \
    -d "$body" "$AUTH/v1/oauth/create-code" | jq -r .code)"
  curl -sf -d "client_id=$1" -d "client_secret=$2" -d grant_type=authorization_code -d "code=$code" \
    -d redirect_uri=http://127.0.0.1/callback -d "code_verifier=$verifier" \
    "$AUTH/v1/oauth/token"
}

echo "3. person token (authorization_code + PKCE, RFC 8707 resource) → Brain"
QS_SECRET="$(secret TRIAD_QUICKSTART_CLIENT_SECRET)"
P_BRAIN_RES="$(person_token triad-quickstart "$QS_SECRET" \
  'openid offline_access brain:read brain:write' "$BRAIN_PUBLIC/mcp")"
P_BRAIN="$(echo "$P_BRAIN_RES" | jq -r .access_token)"
[ -n "$P_BRAIN" ] && [ "$P_BRAIN" != null ] || fail "no person token for Brain"
pc="$(claims "$P_BRAIN")"
ok "token: $(echo "$pc" | jq -c '{iss,aud,sub,org,scope}')"
echo "$pc" | jq -e '.org' >/dev/null || fail "no org claim — is RBAC_TOKEN_CLAIMS_ENABLED=true on Auth?"
n="$(mcp "$P_BRAIN" '{"jsonrpc":"2.0","id":3,"method":"tools/list"}' | jq '.result.tools | length')"
[ "${n:-0}" -gt 0 ] && ok "Brain tools/list as the person (tenant $(echo "$pc" | jq -r .org)): $n tools" || fail "person tools/list"
# A-2: a refreshed token keeps the RFC 8707 audience (auth ≥ 1.12.0, auth #217).
RT="$(echo "$P_BRAIN_RES" | jq -r .refresh_token)"
[ -n "$RT" ] && [ "$RT" != null ] || fail "no refresh_token (offline_access)"
P_REFRESHED="$(curl -sf -d client_id=triad-quickstart -d "client_secret=$QS_SECRET" \
  -d grant_type=refresh_token -d "refresh_token=$RT" "$AUTH/v1/oauth/token" | jq -r .access_token)"
ra="$(claims "$P_REFRESHED" | jq -r .aud)"
[ "$ra" = "$BRAIN_PUBLIC/mcp" ] && ok "refreshed token keeps aud=$ra" || fail "refreshed aud=$ra (contract A-2)"
n="$(mcp "$P_REFRESHED" '{"jsonrpc":"2.0","id":5,"method":"tools/list"}' | jq '.result.tools | length')"
[ "${n:-0}" -gt 0 ] && ok "Brain accepts the refreshed token: $n tools" || fail "Brain refused the refreshed token"

echo "4. person token (client inite-billing) → Billing"
P_BILL="$(person_token inite-billing "$(secret INITE_BILLING_CLIENT_SECRET)" 'openid profile email' | jq -r .access_token)"
[ -n "$P_BILL" ] && [ "$P_BILL" != null ] || fail "no person token for Billing"
ok "token: $(claims "$P_BILL" | jq -c '{iss,aud,sub}')"
r="$(curl -s -w '\n%{http_code}' -H "authorization: Bearer $P_BILL" "$BILLING/v1/credits/me")"
[ "$(echo "$r" | tail -1)" = 200 ] && ok "Billing GET /v1/credits/me → 200 $(echo "$r" | sed '$d' | jq -c . 2>/dev/null)" \
  || fail "Billing /v1/credits/me → $(echo "$r" | tail -1) $(echo "$r" | sed '$d')"

echo "5. audience isolation (tokens are single-audience, A-7)"
c="$(status -H "authorization: Bearer $P_BRAIN" "$BILLING/v1/credits/me")"
[ "$c" = 401 ] && ok "Brain token on Billing → 401" || fail "Brain token on Billing → $c"
c="$(status -X POST "$BRAIN/mcp" -H "authorization: Bearer $P_BILL" -H 'content-type: application/json' \
  -H 'accept: application/json, text/event-stream' -d '{"jsonrpc":"2.0","id":4,"method":"tools/list"}')"
[ "$c" = 401 ] && ok "Billing token on Brain → 401" || fail "Billing token on Brain → $c"
c="$(status -H "authorization: Bearer $SESSION" "$BILLING/v1/credits/me")"
[ "$c" = 401 ] && ok "Auth session token (no aud) on Billing → 401" || fail "session token on Billing → $c"

echo
echo "All checks passed: one issuer ($ISSUER), Brain and Billing verify its tokens."
