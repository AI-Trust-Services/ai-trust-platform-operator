#!/bin/bash
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
f(){ grep -avi memcache; }
DBURL=$(kubectl -n "$NS" get secret app-secrets -o jsonpath='{.data.DATABASE_URL}' 2>/dev/null | base64 -d)
# Run the db-migrate image once with TARGET_SCHEMA=tenant_probe, capture ALL alembic output.
echo "=== run alembic upgrade head with TARGET_SCHEMA=tenant_probe (verbose) ==="
kubectl -n "$NS" run mprobe-$RANDOM --rm -i --restart=Never --image="$REGISTRY/aitrust-db-migrate:$TAG" --quiet \
  --env="DATABASE_URL=$DBURL" --env="TARGET_SCHEMA=tenant_probe" \
  --command -- sh -c 'python -c "import asyncio,os; from sqlalchemy import text; from ai_trust_persistence.database import engine
async def m():
 async with engine.begin() as c: await c.execute(text(\"CREATE SCHEMA IF NOT EXISTS tenant_probe\"))
 await engine.dispose()
asyncio.run(m()); print(\"schema pre-created\")"; alembic -c alembic.ini upgrade head 2>&1 | tail -25' 2>&1 | f

echo; echo "=== tables in tenant_probe (expect ~15) ==="
PGPOD=$(kubectl -n "$NS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep -E '^postgres' | awk '{print $1}' | head -1)
kubectl -n "$NS" exec "$PGPOD" -- sh -lc 'PGPASSWORD=$POSTGRES_PASSWORD psql -U $POSTGRES_USER -d $POSTGRES_DB -tAc "SELECT count(*) FROM information_schema.tables WHERE table_schema='"'"'tenant_probe'"'"'"' 2>&1 | f
echo "=== cleanup probe schema ==="
kubectl -n "$NS" exec "$PGPOD" -- sh -lc 'PGPASSWORD=$POSTGRES_PASSWORD psql -U $POSTGRES_USER -d $POSTGRES_DB -c "DROP SCHEMA IF EXISTS tenant_probe CASCADE"' 2>&1 | f
echo DONE
