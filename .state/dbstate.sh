#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
PGPOD=$(kubectl -n "$NS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep -E '^postgres' | awk '{print $1}' | head -1)
run(){ kubectl -n "$NS" exec "$PGPOD" -- sh -lc "PGPASSWORD=\$POSTGRES_PASSWORD psql -tA -U \$POSTGRES_USER -d ai_trust -c \"$1\"" 2>&1 | grep -avi memcache; }
echo "=== does ai_trust exist + what tables does it have NOW? ==="
run "SELECT count(*) AS table_count FROM pg_tables WHERE schemaname='public';"
run "SELECT string_agg(tablename,', ') FROM pg_tables WHERE schemaname='public';"
echo "=== alembic version (empty = fresh/dropped-recreated; 0009 = old survived) ==="
run "SELECT version_num FROM alembic_version;" 2>&1 | head -2
echo DONE
