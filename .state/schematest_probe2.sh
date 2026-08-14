#!/bin/bash
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh
load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
DBURL="$(kubectl -n $NS get secret app-secrets -o jsonpath='{.data.DATABASE_URL}' 2>/dev/null | base64 -d)"
PGPOD="$(kubectl -n $NS get pods -o name 2>/dev/null | grep -avi memcache | grep postgres | head -1 | sed 's#pod/##')"

# clean
kubectl -n $NS exec "$PGPOD" -- sh -lc 'PGPASSWORD=$POSTGRES_PASSWORD psql -U $POSTGRES_USER -d $POSTGRES_DB -tAc "DROP SCHEMA IF EXISTS tenant_probe CASCADE"' 2>&1 | grep -avi memcache

POD="mprobe-$RANDOM"
kubectl -n $NS run "$POD" --rm -i --restart=Never --image="$REGISTRY/aitrust-db-migrate:$TAG" --quiet \
  --env="DATABASE_URL=$DBURL" --env="TARGET_SCHEMA=tenant_probe" --command -- sh -c '
python -c "import asyncio,os;from sqlalchemy import text;from ai_trust_persistence.database import engine
async def m():
 async with engine.begin() as c: await c.execute(text(\"CREATE SCHEMA IF NOT EXISTS tenant_probe\"))
 await engine.dispose()
asyncio.run(m())"
echo RUN_ALEMBIC
alembic -c alembic.ini upgrade head 2>&1 | grep -iE "error|traceback|except|psycopg|asyncpg|does not exist|already exists|relation|schema|line [0-9]" | head -40
echo POST_CHECK
python -c "import asyncio,os;from sqlalchemy import text;from ai_trust_persistence.database import engine
async def m():
 async with engine.connect() as c:
  r=await c.execute(text(\"SELECT table_schema, count(*) FROM information_schema.tables WHERE table_schema IN (:a,:b) GROUP BY 1\"),{\"a\":\"tenant_probe\",\"b\":\"public\"})
  print(\"COUNTS\", r.fetchall())
 await engine.dispose()
asyncio.run(m())"
' 2>&1 | grep -avi memcache
