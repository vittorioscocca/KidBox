#!/bin/sh
# Xcode Cloud: dopo il clone, opzionalmente genera Facebook.local.xcconfig dai secret del workflow.
# In Xcode Cloud → Workflow → Environment → aggiungi (come Secret):
#   FACEBOOK_APP_ID_LOCAL
#   FACEBOOK_CLIENT_TOKEN_LOCAL

set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Repo layout: <git-root>/KidBox/KidBox/Facebook*.xcconfig (due cartelle KidBox annidate)
CONFIG="$ROOT/KidBox/KidBox/Facebook.local.xcconfig"

if [ -n "${FACEBOOK_APP_ID_LOCAL:-}" ] && [ -n "${FACEBOOK_CLIENT_TOKEN_LOCAL:-}" ]; then
  cat > "$CONFIG" <<EOF
// Generato da ci_post_clone.sh (Xcode Cloud) — non modificare manualmente in CI.
FACEBOOK_APP_ID_LOCAL = ${FACEBOOK_APP_ID_LOCAL}
FACEBOOK_CLIENT_TOKEN_LOCAL = ${FACEBOOK_CLIENT_TOKEN_LOCAL}
EOF
  echo "ci_post_clone: Facebook.local.xcconfig aggiornato da env (Xcode Cloud)."
fi
