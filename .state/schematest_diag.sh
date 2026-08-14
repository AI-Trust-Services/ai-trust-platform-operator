#!/bin/bash
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh
load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
DBURL="$(kubectl -n $NS get secret app-secrets -o jsonpath='{.data.DATABASE_URL}' 2>/dev/null | base64 -d)"
PGPOD="$(kubectl -n $NS get pods -o name 2>/dev/null | grep -avi memcache | grep postgres | head -1 | sed 's#pod/##')"
kubectl -n $NS exec "$PGPOD" -- sh -lc 'PGPASSWORD=$POSTGRES_PASSWORD psql -U $POSTGRES_USER -d $POSTGRES_DB -tAc "DROP SCHEMA IF EXISTS tenant_probe CASCADE"' 2>&1 | grep -avi memcache

POD="mprobe-$RANDOM"
kubectl -n $NS run "$POD" --rm -i --restart=Never --image="$REGISTRY/aitrust-db-migrate:$TAG" --quiet \
  --env="DATABASE_URL=$DBURL" --env="TARGET_SCHEMA=tenant_probe" --command -- python -c '
import asyncio
from sqlalchemy import text
from ai_trust_persistence.database import engine

def sync_probe(conn):
    conn.execute(text("CREATE SCHEMA IF NOT EXISTS \"tenant_probe\""))
    conn.execute(text("SELECT set_config(\x27search_path\x27, :sp, false)"), {"sp": "\"tenant_probe\",public"})
    c2 = conn.execution_options(schema_translate_map={None: "tenant_probe"})
    print("search_path on parent:", conn.exec_driver_sql("SHOW search_path").scalar())
    print("search_path on branch:", c2.exec_driver_sql("SHOW search_path").scalar())
    # emulate a Core create via metadata into a fresh table
    from sqlalchemy import Table, Column, Integer, MetaData
    md = MetaData()
    Table("probe_core_tbl", md, Column("id", Integer, primary_key=True))
    md.create_all(c2)
    # emulate raw op.execute with bare name
    c2.execute(text("CREATE TABLE probe_raw_tbl (id int)"))
    r = c2.execute(text("SELECT table_schema, table_name FROM information_schema.tables WHERE table_name LIKE \x27probe_%\x27"))
    print("PROBE_TABLES", r.fetchall())

async def main():
    async with engine.connect() as ac:
        await ac.run_sync(sync_probe)
        await ac.commit()
    async with engine.connect() as ac:
        r = await ac.execute(text("SELECT table_schema, table_name FROM information_schema.tables WHERE table_name LIKE :p"), {"p":"probe_%"})
        print("AFTER_COMMIT", r.fetchall())
    await engine.dispose()

asyncio.run(main())
' 2>&1 | grep -avi memcache
