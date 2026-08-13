#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
PGPOD=$(kubectl -n "$NS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep -E '^postgres' | awk '{print $1}' | head -1)
run(){ kubectl -n "$NS" exec "$PGPOD" -- sh -lc "PGPASSWORD=\$POSTGRES_PASSWORD psql -U \$POSTGRES_USER -d \$POSTGRES_DB -tA -c \"$1\"" 2>&1 | grep -avi memcache; }
echo "=== does custom_roles exist? all public tables ==="
run "SELECT tablename FROM pg_tables WHERE schemaname='public' ORDER BY 1;"
echo "=== alembic version ==="
run "SELECT version_num FROM alembic_version;"
echo DONE
