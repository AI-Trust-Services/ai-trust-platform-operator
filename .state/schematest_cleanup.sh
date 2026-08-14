#!/bin/bash
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh
load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
PGPOD="$(kubectl -n $NS get pods -o name 2>/dev/null | grep -avi memcache | grep postgres | head -1 | sed 's#pod/##')"
kubectl -n $NS delete job mprobejob --ignore-not-found 2>&1 | grep -avi memcache
kubectl -n $NS exec "$PGPOD" -- sh -lc 'PGPASSWORD=$POSTGRES_PASSWORD psql -U $POSTGRES_USER -d $POSTGRES_DB -tAc "DROP SCHEMA IF EXISTS tenant_probe CASCADE"' 2>&1 | grep -avi memcache
echo "--- public table count (should still be 15) ---"
kubectl -n $NS exec "$PGPOD" -- sh -lc 'PGPASSWORD=$POSTGRES_PASSWORD psql -U $POSTGRES_USER -d $POSTGRES_DB -tAc "SELECT count(*) FROM information_schema.tables WHERE table_schema='\''public'\''"' 2>&1 | grep -avi memcache
echo "--- remaining schemas ---"
kubectl -n $NS exec "$PGPOD" -- sh -lc 'PGPASSWORD=$POSTGRES_PASSWORD psql -U $POSTGRES_USER -d $POSTGRES_DB -tAc "SELECT schema_name FROM information_schema.schemata WHERE schema_name LIKE '\''tenant%'\''"' 2>&1 | grep -avi memcache
echo "CLEANUP_DONE"
