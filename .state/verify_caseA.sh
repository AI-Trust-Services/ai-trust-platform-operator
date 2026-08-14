#!/bin/bash
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
f(){ grep -avi memcache; }
PGPOD=$(kubectl -n "$NS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep -E '^postgres' | awk '{print $1}' | head -1)
APPPW=$(kubectl -n "$NS" get secret app-secrets -o jsonpath='{.data.APP_DATABASE_URL}' 2>/dev/null | base64 -d | sed -E 's#.*://ai_trust_app:([^@]*)@.*#\1#')
# Single fresh connection, ONLY the cross-tenant query, nothing else. Definitive.
echo "=== fresh ai_trust_app connection, NO set role, straight at tenant_sohan.ai_systems ==="
kubectl -n "$NS" exec "$PGPOD" -- sh -lc "PGPASSWORD='$APPPW' psql -h localhost -U ai_trust_app -d \$POSTGRES_DB -c 'SELECT count(*) FROM tenant_sohan.ai_systems'" 2>&1 | f
echo "--- exit code above should be an ERROR permission denied ---"
echo "=== also try a plain unqualified select after setting search_path to sohan (no role) ==="
kubectl -n "$NS" exec "$PGPOD" -- sh -lc "PGPASSWORD='$APPPW' psql -h localhost -U ai_trust_app -d \$POSTGRES_DB -c \"SET search_path TO tenant_sohan; SELECT count(*) FROM ai_systems\"" 2>&1 | f
echo DONE
