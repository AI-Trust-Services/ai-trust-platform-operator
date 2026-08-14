#!/bin/bash
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh
load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
K(){ kubectl "$@" 2>&1 | grep -avi memcache; }

DBURL="$(kubectl -n $NS get secret app-secrets -o jsonpath='{.data.DATABASE_URL}' 2>/dev/null | base64 -d)"
[ -n "$DBURL" ] || { echo "NO DBURL"; exit 1; }

PGPOD="$(kubectl -n $NS get pods -o name 2>/dev/null | grep -avi memcache | grep postgres | head -1 | sed 's#pod/##')"
echo "PGPOD=$PGPOD"

echo "=== DROP tenant_probe first (clean slate) ==="
kubectl -n $NS exec "$PGPOD" -- sh -lc 'PGPASSWORD=$POSTGRES_PASSWORD psql -U $POSTGRES_USER -d $POSTGRES_DB -tAc "DROP SCHEMA IF EXISTS tenant_probe CASCADE"' 2>&1 | grep -avi memcache

echo "=== public table count BEFORE ==="
PUB_BEFORE=$(kubectl -n $NS exec "$PGPOD" -- sh -lc 'PGPASSWORD=$POSTGRES_PASSWORD psql -U $POSTGRES_USER -d $POSTGRES_DB -tAc "SELECT count(*) FROM information_schema.tables WHERE table_schema='\''public'\''"' 2>&1 | grep -avi memcache | tr -d '[:space:]')
echo "PUB_BEFORE=$PUB_BEFORE"

echo "=== run migrations into tenant_probe ==="
POD="mprobe-$RANDOM"
kubectl -n $NS run "$POD" --rm -i --restart=Never --image="$REGISTRY/aitrust-db-migrate:$TAG" --image-pull-policy=Always --quiet \
  --env="DATABASE_URL=$DBURL" --env="TARGET_SCHEMA=tenant_probe" --command -- sh -c '
python -c "import asyncio,os;from sqlalchemy import text;from ai_trust_persistence.database import engine
async def m():
 async with engine.begin() as c: await c.execute(text(\"CREATE SCHEMA IF NOT EXISTS tenant_probe\"))
 await engine.dispose()
asyncio.run(m())"
alembic -c alembic.ini upgrade head 2>&1 | tail -25
' 2>&1 | grep -avi memcache

echo "=== VERIFY tenant_probe ==="
echo -n "tenant_probe tables: "
kubectl -n $NS exec "$PGPOD" -- sh -lc 'PGPASSWORD=$POSTGRES_PASSWORD psql -U $POSTGRES_USER -d $POSTGRES_DB -tAc "SELECT count(*) FROM information_schema.tables WHERE table_schema='\''tenant_probe'\''"' 2>&1 | grep -avi memcache | tr -d '[:space:]'; echo
echo -n "tenant_probe policies: "
kubectl -n $NS exec "$PGPOD" -- sh -lc 'PGPASSWORD=$POSTGRES_PASSWORD psql -U $POSTGRES_USER -d $POSTGRES_DB -tAc "SELECT count(*) FROM pg_policies WHERE schemaname='\''tenant_probe'\''"' 2>&1 | grep -avi memcache | tr -d '[:space:]'; echo
echo -n "tenant_probe alembic_version: "
kubectl -n $NS exec "$PGPOD" -- sh -lc 'PGPASSWORD=$POSTGRES_PASSWORD psql -U $POSTGRES_USER -d $POSTGRES_DB -tAc "SELECT version_num FROM tenant_probe.alembic_version"' 2>&1 | grep -avi memcache | tr -d '[:space:]'; echo
echo -n "public table count AFTER: "
PUB_AFTER=$(kubectl -n $NS exec "$PGPOD" -- sh -lc 'PGPASSWORD=$POSTGRES_PASSWORD psql -U $POSTGRES_USER -d $POSTGRES_DB -tAc "SELECT count(*) FROM information_schema.tables WHERE table_schema='\''public'\''"' 2>&1 | grep -avi memcache | tr -d '[:space:]')
echo "$PUB_AFTER (before was $PUB_BEFORE)"
echo -n "tenant_probe table list: "
kubectl -n $NS exec "$PGPOD" -- sh -lc 'PGPASSWORD=$POSTGRES_PASSWORD psql -U $POSTGRES_USER -d $POSTGRES_DB -tAc "SELECT string_agg(table_name,'\'','\'') FROM information_schema.tables WHERE table_schema='\''tenant_probe'\''"' 2>&1 | grep -avi memcache
