#!/bin/bash
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
f(){ grep -avi memcache; }
PGPOD=$(kubectl -n "$NS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep -E '^postgres' | awk '{print $1}' | head -1)
echo "=== ALTER ROLE ai_trust_app NOINHERIT (must SET ROLE explicitly; no ambient tenant access) ==="
kubectl -n "$NS" exec "$PGPOD" -- sh -lc 'PGPASSWORD=$POSTGRES_PASSWORD psql -U $POSTGRES_USER -d $POSTGRES_DB -c "ALTER ROLE ai_trust_app NOINHERIT"' 2>&1 | f
echo "=== re-test: WITHOUT set role → tenant_sohan must be DENIED now ==="
kubectl -n "$NS" exec "$PGPOD" -- sh -lc 'PGPASSWORD=$POSTGRES_PASSWORD psql -U $POSTGRES_USER -d $POSTGRES_DB <<SQL 2>&1
SET ROLE ai_trust_app;
SELECT '"'"'no-set-role tenant_sohan (expect DENIED):'"'"';
SELECT count(*) FROM tenant_sohan.ai_systems;
SQL' 2>&1 | f
echo "=== re-test: WITH set role t_sohan → own schema OK ==="
kubectl -n "$NS" exec "$PGPOD" -- sh -lc 'PGPASSWORD=$POSTGRES_PASSWORD psql -U $POSTGRES_USER -d $POSTGRES_DB <<SQL 2>&1
SET ROLE ai_trust_app; SET ROLE t_sohan;
SELECT '"'"'set-role t_sohan own (ok):'"'"', count(*) FROM tenant_sohan.ai_systems;
SELECT '"'"'set-role t_sohan cross tenant_mirceatest (expect DENIED):'"'"';
SELECT count(*) FROM tenant_mirceatest.ai_systems;
SQL' 2>&1 | f
echo DONE
