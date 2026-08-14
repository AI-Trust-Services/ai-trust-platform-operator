#!/bin/bash
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
f(){ grep -avi memcache; }
PGPOD=$(kubectl -n "$NS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep -E '^postgres' | awk '{print $1}' | head -1)
PSQL() { kubectl -n "$NS" exec "$PGPOD" -- sh -lc "PGPASSWORD=\$POSTGRES_PASSWORD psql -U \$POSTGRES_USER -d \$POSTGRES_DB -tAc \"$1\"" 2>&1 | f; }

echo "=== per-tenant schemas + table + policy counts ==="
for S in tenant_livedemo tenant_mirceatest tenant_mttest2 tenant_sohan; do
  T=$(PSQL "SELECT count(*) FROM information_schema.tables WHERE table_schema='$S'")
  P=$(PSQL "SELECT count(*) FROM pg_policies WHERE schemaname='$S'")
  V=$(PSQL "SELECT version_num FROM $S.alembic_version" 2>/dev/null)
  echo "  $S : tables=$T  rls_policies=$P  alembic=$V"
done

echo; echo "=== ISOLATION TEST: as ai_trust_app with search_path=tenant_mirceatest, can it touch tenant_sohan? ==="
kubectl -n "$NS" exec "$PGPOD" -- sh -lc 'PGPASSWORD=$POSTGRES_PASSWORD psql -U $POSTGRES_USER -d $POSTGRES_DB -c "
SET ROLE ai_trust_app;
SET search_path TO tenant_mirceatest, public;
SELECT '"'"'own schema ai_systems count'"'"', count(*) FROM ai_systems;
SELECT '"'"'cross-tenant attempt (should ERROR: permission denied)'"'"';
SELECT count(*) FROM tenant_sohan.ai_systems;
"' 2>&1 | f
echo DONE
