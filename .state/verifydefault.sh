#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
PGPOD=$(kubectl -n "$NS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep -E '^postgres' | awk '{print $1}' | head -1)
run(){ kubectl -n "$NS" exec "$PGPOD" -- sh -lc "PGPASSWORD=\$POSTGRES_PASSWORD psql -U \$POSTGRES_USER -d \$POSTGRES_DB -tA -c \"$1\"" 2>&1 | grep -avi memcache; }
echo "=== alembic version (expect 0009) ==="; run "SELECT version_num FROM alembic_version;"
echo "=== tenant_id defaults now set? (expect current_setting default on all 11) ==="
run "SELECT table_name||' -> '||COALESCE(column_default,'<none>') FROM information_schema.columns WHERE table_schema='public' AND column_name='tenant_id' ORDER BY table_name;"
echo DONE
