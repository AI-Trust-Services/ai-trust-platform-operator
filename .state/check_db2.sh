#!/bin/bash
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
f(){ grep -avi memcache; }
PGPOD=$(kubectl -n "$NS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep -E '^postgres' | awk '{print $1}' | head -1)
echo "postgres pod: $PGPOD"
echo "=== non-system schemas (expect just 'public' — NO per-tenant schemas) ==="
kubectl -n "$NS" exec "$PGPOD" -- psql -U euaiact -d ai_trust -tAc "SELECT schema_name FROM information_schema.schemata WHERE schema_name NOT LIKE 'pg_%' AND schema_name<>'information_schema'" 2>&1 | f
echo "=== tables with RLS enabled in public ==="
kubectl -n "$NS" exec "$PGPOD" -- psql -U euaiact -d ai_trust -tAc "SELECT tablename FROM pg_tables WHERE schemaname='public' AND rowsecurity=true ORDER BY 1" 2>&1 | f
echo "=== distinct tenant_id values present in ai_systems (shows multiple tenants share the table) ==="
kubectl -n "$NS" exec "$PGPOD" -- psql -U euaiact -d ai_trust -tAc "SELECT COALESCE(tenant_id,'<NULL/shared>') AS t, count(*) FROM ai_systems GROUP BY 1 ORDER BY 1" 2>&1 | f
echo DONE
