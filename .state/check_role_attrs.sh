#!/bin/bash
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
f(){ grep -avi memcache; }
PGPOD=$(kubectl -n "$NS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep -E '^postgres' | awk '{print $1}' | head -1)
echo "=== ai_trust_app full role attributes ==="
kubectl -n "$NS" exec "$PGPOD" -- sh -lc 'PGPASSWORD=$POSTGRES_PASSWORD psql -U $POSTGRES_USER -d $POSTGRES_DB -tAc "SELECT rolname,rolsuper,rolinherit,rolbypassrls,rolcanlogin FROM pg_roles WHERE rolname='"'"'ai_trust_app'"'"'"' 2>&1 | f
echo "  (rolsuper or rolbypassrls = t would explain why it sees everything)"
echo "=== what does the app's APP_DATABASE_URL user actually resolve to? (is it really ai_trust_app?) ==="
kubectl -n "$NS" exec "$PGPOD" -- sh -lc "PGPASSWORD=\$(kubectl 2>/dev/null; echo skip)" 2>/dev/null || true
APPURL=$(kubectl -n "$NS" get secret app-secrets -o jsonpath='{.data.APP_DATABASE_URL}' 2>/dev/null | base64 -d)
echo "  APP_DATABASE_URL user = $(echo "$APPURL" | sed -E 's#.*://([^:]*):.*#\1#')"
echo "=== current_user when connected via that url ==="
APPPW=$(echo "$APPURL" | sed -E 's#.*://[^:]*:([^@]*)@.*#\1#')
APPUSER=$(echo "$APPURL" | sed -E 's#.*://([^:]*):.*#\1#')
kubectl -n "$NS" exec "$PGPOD" -- sh -lc "PGPASSWORD='$APPPW' psql -h localhost -U '$APPUSER' -d \$POSTGRES_DB -tAc 'SELECT current_user, session_user, rolsuper FROM pg_roles WHERE rolname=current_user'" 2>&1 | f
echo DONE
