#!/usr/bin/env bash
# dev.sh — spin up a Keycloak container with the glassy theme mounted and
# pre-configure a test realm + client + user so you can visit the login page
# in one click. Re-runnable (idempotent): each `up` wipes the previous container.
#
# Usage:
#   ./dev.sh            # or: ./dev.sh up    — start + configure
#   ./dev.sh down                             — stop and remove the container
#   ./dev.sh logs                             — follow container logs
#
# Env overrides: IMAGE, PORT, REALM, CLIENT_ID, USERNAME, PASSWORD, RUNTIME
set -euo pipefail

# --- Configuration ---
CONTAINER=${CONTAINER:-kc-test}
IMAGE=${IMAGE:-quay.io/keycloak/keycloak:26.5.6}
PORT=${PORT:-18080}
REALM=${REALM:-test}
CLIENT_ID=${CLIENT_ID:-testclient}
USERNAME=${USERNAME:-testuser}
PASSWORD=${PASSWORD:-testpass}
ADMIN_USER=${ADMIN_USER:-admin}
ADMIN_PASS=${ADMIN_PASS:-admin}

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
THEME_DIR="${REPO_DIR}/login"
KC_URL="http://localhost:${PORT}"

# --- Auto-detect container runtime ---
if [ -n "${RUNTIME:-}" ]; then
  :
elif command -v docker >/dev/null 2>&1; then
  RUNTIME=docker
elif command -v podman >/dev/null 2>&1; then
  RUNTIME=podman
else
  echo "error: neither docker nor podman found in PATH" >&2
  exit 1
fi

# --- Subcommand dispatch ---
cmd=${1:-up}
case "$cmd" in
  down)
    echo "Removing container ${CONTAINER}..."
    $RUNTIME rm -f "$CONTAINER" >/dev/null 2>&1 || true
    echo "Done."
    exit 0
    ;;
  logs)
    exec $RUNTIME logs -f "$CONTAINER"
    ;;
  up) ;;
  -h|--help|help)
    sed -n '2,13p' "$0"
    exit 0
    ;;
  *)
    echo "Usage: $0 [up|down|logs]" >&2
    exit 1
    ;;
esac

if [ ! -d "$THEME_DIR" ]; then
  echo "error: theme dir not found at $THEME_DIR" >&2
  exit 1
fi

# --- Start (fresh) Keycloak ---
$RUNTIME rm -f "$CONTAINER" >/dev/null 2>&1 || true

echo "Starting Keycloak ${IMAGE} on port ${PORT} (runtime: ${RUNTIME})..."
$RUNTIME run -d --name "$CONTAINER" \
  -p "${PORT}:8080" \
  -e KC_BOOTSTRAP_ADMIN_USERNAME="$ADMIN_USER" \
  -e KC_BOOTSTRAP_ADMIN_PASSWORD="$ADMIN_PASS" \
  -v "${THEME_DIR}:/opt/keycloak/themes/glassy/login:ro,Z" \
  "$IMAGE" start-dev >/dev/null

# --- Wait for Keycloak to be ready ---
printf "Waiting for Keycloak"
for i in $(seq 1 90); do
  if curl -sf "${KC_URL}/realms/master/.well-known/openid-configuration" >/dev/null 2>&1; then
    printf " ready.\n"
    break
  fi
  printf "."
  sleep 2
  if [ "$i" -eq 90 ]; then
    printf "\n"
    echo "error: Keycloak did not become ready in time" >&2
    $RUNTIME logs "$CONTAINER" | tail -30
    exit 1
  fi
done

# --- Get admin token (no external deps: parse JSON with sed) ---
TOKEN=$(
  curl -sf -X POST "${KC_URL}/realms/master/protocol/openid-connect/token" \
    -d "username=${ADMIN_USER}" \
    -d "password=${ADMIN_PASS}" \
    -d "grant_type=password" \
    -d "client_id=admin-cli" \
  | sed -n 's/.*"access_token":"\([^"]*\)".*/\1/p'
)
if [ -z "$TOKEN" ]; then
  echo "error: failed to obtain admin token" >&2
  exit 1
fi
AUTH="Authorization: Bearer $TOKEN"

# Call the admin API; return HTTP status. Accepts 2xx and 409 (already exists).
api() {
  local method=$1 path=$2 body=${3:-}
  local status
  if [ -n "$body" ]; then
    status=$(curl -sS -o /dev/null -w '%{http_code}' \
      -X "$method" "${KC_URL}${path}" \
      -H "$AUTH" -H "Content-Type: application/json" \
      -d "$body")
  else
    status=$(curl -sS -o /dev/null -w '%{http_code}' \
      -X "$method" "${KC_URL}${path}" \
      -H "$AUTH")
  fi
  case "$status" in
    2*|409) echo "$status" ;;
    *)
      echo "error: $method $path returned HTTP $status" >&2
      return 1
      ;;
  esac
}

echo "Creating realm '${REALM}' with loginTheme=glassy..."
api POST /admin/realms "{
  \"realm\":\"${REALM}\",
  \"enabled\":true,
  \"loginTheme\":\"glassy\",
  \"registrationAllowed\":true,
  \"rememberMe\":true,
  \"resetPasswordAllowed\":true,
  \"internationalizationEnabled\":true,
  \"supportedLocales\":[\"en\",\"fr\"],
  \"defaultLocale\":\"en\"
}" >/dev/null

# Always PUT so the theme sticks even on a re-run where the realm already exists
api PUT "/admin/realms/${REALM}" "{
  \"realm\":\"${REALM}\",
  \"loginTheme\":\"glassy\",
  \"registrationAllowed\":true,
  \"rememberMe\":true,
  \"resetPasswordAllowed\":true,
  \"internationalizationEnabled\":true
}" >/dev/null

echo "Creating client '${CLIENT_ID}' (public, no PKCE)..."
api POST "/admin/realms/${REALM}/clients" "{
  \"clientId\":\"${CLIENT_ID}\",
  \"enabled\":true,
  \"publicClient\":true,
  \"standardFlowEnabled\":true,
  \"directAccessGrantsEnabled\":true,
  \"redirectUris\":[\"http://localhost:${PORT}/*\"],
  \"webOrigins\":[\"*\"],
  \"attributes\":{\"pkce.code.challenge.method\":\"\"}
}" >/dev/null

echo "Creating user '${USERNAME}' (password: ${PASSWORD})..."
api POST "/admin/realms/${REALM}/users" "{
  \"username\":\"${USERNAME}\",
  \"enabled\":true,
  \"emailVerified\":true,
  \"email\":\"${USERNAME}@example.com\",
  \"firstName\":\"Test\",
  \"lastName\":\"User\",
  \"credentials\":[{\"type\":\"password\",\"value\":\"${PASSWORD}\",\"temporary\":false}]
}" >/dev/null

LOGIN_URL="${KC_URL}/realms/${REALM}/protocol/openid-connect/auth?client_id=${CLIENT_ID}&redirect_uri=http%3A%2F%2Flocalhost%3A${PORT}%2F&response_type=code&scope=openid&state=xyz"

cat <<EOF

===============================================================
 Keycloak is up with the glassy theme pre-configured.

   Login page:     ${LOGIN_URL}
   Admin console:  ${KC_URL}/admin/   (${ADMIN_USER} / ${ADMIN_PASS})
   Test user:      ${USERNAME} / ${PASSWORD}

 Edit files under ${THEME_DIR}/
 and just reload the page — start-dev disables the theme cache.

   Logs:    $0 logs
   Stop:    $0 down
===============================================================
EOF
