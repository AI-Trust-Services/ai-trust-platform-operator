#!/bin/bash
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh 2>/dev/null; load_config 2>/dev/null
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
f(){ grep -avi memcache; }

echo "=== overview bundle: is the UNRESOLVED literal token \"VITE_USERS_API_BASE\" still present? ==="
echo "    (present = NOT baked/throws; absent + api/users/v1 = baked/fixed)"
kubectl -n "$NS" exec deploy/overview-frontend -- sh -c '
  if grep -rhoE "VITE_USERS_API_BASE" /usr/share/nginx/html/assets/*.js >/dev/null 2>&1; then
    echo "  literal VITE_USERS_API_BASE: STILL PRESENT (bad)"
  else
    echo "  literal VITE_USERS_API_BASE: gone (good)"
  fi
  echo "  api/users/v1 baked: $(grep -rhoE "api/users/v1" /usr/share/nginx/html/assets/*.js 2>/dev/null | sort -u | head -1)"
' 2>&1 | f

echo; echo "=== cross-check: known-good users-frontend has the SAME requireEnv error string? (proves the string is a red herring) ==="
kubectl -n "$NS" exec deploy/users-frontend -- sh -c 'grep -rIl "Missing required environment variable" /usr/share/nginx/html/assets/ >/dev/null 2>&1 && echo "  users-frontend ALSO contains the error string (confirms: it is a generic helper, not a live throw)" || echo "  users-frontend has no such string"' 2>&1 | f
echo DONE
