#!/bin/bash
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
f(){ grep -avi memcache; }
PGPOD=$(kubectl -n "$NS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep -E '^postgres' | awk '{print $1}' | head -1)
echo "postgres pod: $PGPOD"
kubectl -n "$NS" exec "$PGPOD" -- sh -lc 'PGPASSWORD=$POSTGRES_PASSWORD psql -U $POSTGRES_USER -d $POSTGRES_DB -tA -c "
SELECT ''schemas:'' , string_agg(schema_name, '','') FROM information_schema.schemata WHERE schema_name NOT LIKE ''pg_%'' AND schema_name <> ''information_schema'';
SELECT ''rls_tables:'', count(*) FROM pg_tables WHERE schemaname=''public'' AND rowsecurity=true;
SELECT ''distinct_tenants_in_ai_systems:'', string_agg(DISTINCT COALESCE(tenant_id,''<NULL/shared>''), '', '') FROM ai_systems;
"' 2>&1 | f
echo DONE
