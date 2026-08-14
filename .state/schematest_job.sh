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

kubectl -n $NS delete job mprobejob --ignore-not-found >/dev/null 2>&1
cat <<YAML | kubectl -n $NS apply -f - 2>&1 | grep -avi memcache
apiVersion: batch/v1
kind: Job
metadata:
  name: mprobejob
spec:
  backoffLimit: 0
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: m
        image: $REGISTRY/aitrust-db-migrate:$TAG
        env:
        - {name: DATABASE_URL, value: "$DBURL"}
        - {name: TARGET_SCHEMA, value: "tenant_probe"}
        command: ["sh","-c"]
        args:
        - |
          python -c "import asyncio;from sqlalchemy import text;from ai_trust_persistence.database import engine
          async def m():
           async with engine.begin() as c: await c.execute(text('CREATE SCHEMA IF NOT EXISTS tenant_probe'))
           await engine.dispose()
          asyncio.run(m())"
          alembic -c alembic.ini upgrade head
          echo EXIT=\$?
YAML
kubectl -n $NS wait --for=condition=complete job/mprobejob --timeout=150s 2>&1 | grep -avi memcache || kubectl -n $NS wait --for=condition=failed job/mprobejob --timeout=10s 2>&1 | grep -avi memcache
echo "=== JOB LOGS ==="
kubectl -n $NS logs job/mprobejob 2>&1 | grep -avi memcache
echo "=== tenant_probe tables ==="
kubectl -n $NS exec "$PGPOD" -- sh -lc 'PGPASSWORD=$POSTGRES_PASSWORD psql -U $POSTGRES_USER -d $POSTGRES_DB -tAc "SELECT count(*) FROM information_schema.tables WHERE table_schema='\''tenant_probe'\''"' 2>&1 | grep -avi memcache
