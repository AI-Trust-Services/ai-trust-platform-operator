#!/bin/bash
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
f(){ grep -avi memcache; }
PGPOD=$(kubectl -n "$NS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep -E '^postgres' | awk '{print $1}' | head -1)
echo "postgres pod: $PGPOD"
# Run psql INSIDE the pod using its own env creds (no creds cross the boundary).
Q1="SELECT schema_name FROM information_schema.schemata WHERE schema_name NOT LIKE 'pg_%' AND schema_name<>'information_schema'"
Q2="SELECT tablename FROM pg_tables WHERE schemaname='public' AND rowsecurity=true ORDER BY 1"
Q3="SELECT COALESCE(tenant_id,'<NULL/shared>'), count(*) FROM ai_systems GROUP BY 1 ORDER BY 1"
echo "=== non-system schemas (expect only public) ==="
kubectl -n "$NS" exec "$PGPOD" -- sh -lc "PGPASSWORD=\$POSTGRES_PASSWORD psql -U \$POSTGRES_USER -d \$POSTGRES_DB -tAc \"$Q1\"" 2>&1 | f
echo "=== RLS-enabled tables in public ==="
kubectl -n "$NS" exec "$PGPOD" -- sh -lc "PGPASSWORD=\$POSTGRES_PASSWORD psql -U \$POSTGRES_USER -d \$POSTGRES_DB -tAc \"$Q2\"" 2>&1 | f
echo "=== tenant_id distribution in ai_systems ==="
kubectl -n "$NS" exec "$PGPOD" -- sh -lc "PGPASSWORD=\$POSTGRES_PASSWORD psql -U \$POSTGRES_USER -d \$POSTGRES_DB -tAc \"$Q3\"" 2>&1 | f
echo DONE
