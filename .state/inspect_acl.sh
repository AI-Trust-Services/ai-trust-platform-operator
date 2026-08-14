#!/bin/bash
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
f(){ grep -avi memcache; }
PGPOD=$(kubectl -n "$NS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep -E '^postgres' | awk '{print $1}' | head -1)
echo "=== nspacl on tenant_sohan (who has USAGE?) ==="
kubectl -n "$NS" exec "$PGPOD" -- sh -lc 'PGPASSWORD=$POSTGRES_PASSWORD psql -U $POSTGRES_USER -d $POSTGRES_DB -tAc "SELECT nspname, nspacl FROM pg_namespace WHERE nspname='"'"'tenant_sohan'"'"'"' 2>&1 | f
echo "  (look for =U/... = PUBLIC has USAGE; ai_trust_app=U/... = direct grant)"
echo "=== does ai_trust_app have DIRECT (non-inherited) usage? check via has with membership stripped ==="
kubectl -n "$NS" exec "$PGPOD" -- sh -lc 'PGPASSWORD=$POSTGRES_PASSWORD psql -U $POSTGRES_USER -d $POSTGRES_DB -tAc "SELECT rolname, rolinherit FROM pg_roles WHERE rolname='"'"'ai_trust_app'"'"'"' 2>&1 | f
echo "=== is USAGE granted to PUBLIC on the tenant schemas? ==="
kubectl -n "$NS" exec "$PGPOD" -- sh -lc 'PGPASSWORD=$POSTGRES_PASSWORD psql -U $POSTGRES_USER -d $POSTGRES_DB -tAc "SELECT has_schema_privilege('"'"'public'"'"', '"'"'tenant_sohan'"'"', '"'"'USAGE'"'"')"' 2>&1 | f
echo DONE
