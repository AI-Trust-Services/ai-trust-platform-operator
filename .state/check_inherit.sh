#!/bin/bash
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
f(){ grep -avi memcache; }
PGPOD=$(kubectl -n "$NS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep -E '^postgres' | awk '{print $1}' | head -1)
echo "=== ai_trust_app INHERIT setting (rolinherit) ==="
kubectl -n "$NS" exec "$PGPOD" -- sh -lc 'PGPASSWORD=$POSTGRES_PASSWORD psql -U $POSTGRES_USER -d $POSTGRES_DB -tAc "SELECT rolname, rolinherit FROM pg_roles WHERE rolname='"'"'ai_trust_app'"'"'"' 2>&1 | f
echo "=== CRITICAL: as ai_trust_app WITHOUT set role, can it read a tenant schema via inheritance? ==="
kubectl -n "$NS" exec "$PGPOD" -- sh -lc 'PGPASSWORD=$POSTGRES_PASSWORD psql -U $POSTGRES_USER -d $POSTGRES_DB <<SQL 2>&1
SET ROLE ai_trust_app;
SELECT '"'"'no-set-role, tenant_sohan (INHERIT hole if this succeeds):'"'"';
SELECT count(*) FROM tenant_sohan.ai_systems;
SQL' 2>&1 | f
echo DONE
