#!/bin/bash
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh
load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
PGPOD="$(kubectl -n $NS get pods -o name 2>/dev/null | grep -avi memcache | grep postgres | head -1 | sed 's#pod/##')"
psqlq(){ kubectl -n $NS exec "$PGPOD" -- sh -lc "PGPASSWORD=\$POSTGRES_PASSWORD psql -U \$POSTGRES_USER -d \$POSTGRES_DB -tAc \"$1\"" 2>&1 | grep -avi memcache; }
echo "=== every schema that has an ai_systems table ==="
psqlq "SELECT table_schema FROM information_schema.tables WHERE table_name='ai_systems'"
echo "=== all schemas ==="
psqlq "SELECT schema_name FROM information_schema.schemata ORDER BY 1"
echo "=== public.alembic_version ==="
psqlq "SELECT version_num FROM public.alembic_version"
echo "=== count tables per schema ==="
psqlq "SELECT table_schema, count(*) FROM information_schema.tables WHERE table_schema NOT IN ('pg_catalog','information_schema') GROUP BY 1"
