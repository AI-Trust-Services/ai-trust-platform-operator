#!/bin/bash
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
f(){ grep -avi memcache; }
PGPOD=$(kubectl -n "$NS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep -E '^postgres' | awk '{print $1}' | head -1)

echo "=== per-tenant roles exist (t_<org>) ==="
kubectl -n "$NS" exec "$PGPOD" -- sh -lc 'PGPASSWORD=$POSTGRES_PASSWORD psql -U $POSTGRES_USER -d $POSTGRES_DB -tAc "SELECT rolname FROM pg_roles WHERE rolname LIKE '"'"'t\_%'"'"' ORDER BY 1"' 2>&1 | f

echo; echo "=== ai_trust_app has NO direct grant on tenant schemas (only membership in t_<org>) ==="
kubectl -n "$NS" exec "$PGPOD" -- sh -lc 'PGPASSWORD=$POSTGRES_PASSWORD psql -U $POSTGRES_USER -d $POSTGRES_DB -tAc "SELECT nspname, has_schema_privilege('"'"'ai_trust_app'"'"', nspname, '"'"'USAGE'"'"') AS direct_usage FROM pg_namespace WHERE nspname LIKE '"'"'tenant_%'"'"' ORDER BY 1"' 2>&1 | f
echo "  (direct_usage should be f/false — access only via SET ROLE)"

echo; echo "=== HARD WALL: ai_trust_app -> SET ROLE t_mirceatest -> own OK, cross DENIED ==="
kubectl -n "$NS" exec "$PGPOD" -- sh -lc 'PGPASSWORD=$POSTGRES_PASSWORD psql -U $POSTGRES_USER -d $POSTGRES_DB <<SQL 2>&1
SET ROLE ai_trust_app;
SET ROLE t_mirceatest;
SELECT '"'"'OWN (ok):'"'"', count(*) FROM tenant_mirceatest.ai_systems;
SELECT '"'"'CROSS tenant_sohan (expect ERROR permission denied):'"'"';
SELECT count(*) FROM tenant_sohan.ai_systems;
SQL' 2>&1 | f

echo; echo "=== also: without SET ROLE (fail-closed path), ai_trust_app on public sees no tenant tables ==="
kubectl -n "$NS" exec "$PGPOD" -- sh -lc 'PGPASSWORD=$POSTGRES_PASSWORD psql -U $POSTGRES_USER -d $POSTGRES_DB <<SQL 2>&1
SET ROLE ai_trust_app; SET search_path TO public;
SELECT '"'"'public.ai_systems still exists (legacy/fallback):'"'"', count(*) FROM ai_systems;
SELECT '"'"'cross tenant_sohan without SET ROLE (expect DENIED):'"'"';
SELECT count(*) FROM tenant_sohan.ai_systems;
SQL' 2>&1 | f
echo DONE
