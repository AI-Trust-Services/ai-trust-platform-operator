#!/bin/bash
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
f(){ grep -avi memcache; }

echo "=== 1) undo manual probe roles + re-grant ai_trust_app so operator re-provisions cleanly ==="
PGPOD=$(kubectl -n "$NS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep -E '^postgres' | awk '{print $1}' | head -1)
kubectl -n "$NS" exec "$PGPOD" -- sh -lc 'PGPASSWORD=$POSTGRES_PASSWORD psql -U $POSTGRES_USER -d $POSTGRES_DB <<SQL 2>&1
-- drop the two manual probe roles (operator will recreate all via the Job); reassign owned first
DROP OWNED BY t_mirceatest; DROP ROLE IF EXISTS t_mirceatest;
DROP OWNED BY t_sohan; DROP ROLE IF EXISTS t_sohan;
SQL' 2>&1 | grep -aviE 'memcache' | tail -5 || true

echo "=== 2) delete tenant-stores jobs so v15 re-stamps with role model ==="
for o in livedemo mirceatest mttest2 sohan; do kubectl -n "$NS" delete job tenant-stores-$o --ignore-not-found 2>&1 | f; done

echo "=== 3) build+push all app images (session.py change hits all backends) from mircea-mt2 HEAD ==="
bash scripts/2b-build-app-images.sh --skip-clone 2>&1 | tail -6
echo "APPS_EXIT: ${PIPESTATUS[0]}"

echo "=== 4) build+push operator v15 ==="
bash scripts/2-build-operator-image.sh 2>&1 | tail -3
echo "OP_EXIT: ${PIPESTATUS[0]}"
