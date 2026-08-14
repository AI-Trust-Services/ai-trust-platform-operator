#!/bin/bash
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
f(){ grep -avi memcache; }

echo "=== wait up to ~90s for tenant-stores jobs to complete ==="
for i in $(seq 1 9); do
  RUN=$(kubectl -n "$NS" get jobs --no-headers 2>/dev/null | grep -avi memcache | grep -i tenant-stores | grep -c Running || true)
  echo "  [$i] tenant-stores jobs still running: $RUN"
  [ "$RUN" = "0" ] && break
  sleep 10
done
echo "-- job statuses --"
kubectl -n "$NS" get jobs --no-headers 2>&1 | f | grep -i tenant-stores

echo; echo "=== one job's log (mirceatest) ==="
kubectl -n "$NS" logs job/tenant-stores-mirceatest --tail=15 2>&1 | f | tail -15

echo; echo "=== subscription phases (expect Ready for the real ones) ==="
kubectl get subscriptions.sub.aitrustmt.msp -A -o jsonpath='{range .items[*]}{.spec.org}={.status.phase}{"\n"}{end}' 2>&1 | f | grep -vE '^=' | sort -u

echo; echo "=== Postgres: schemas now present ==="
PGPOD=$(kubectl -n "$NS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep -E '^postgres' | awk '{print $1}' | head -1)
kubectl -n "$NS" exec "$PGPOD" -- sh -lc 'PGPASSWORD=$POSTGRES_PASSWORD psql -U $POSTGRES_USER -d $POSTGRES_DB -tAc "SELECT schema_name FROM information_schema.schemata WHERE schema_name LIKE '"'"'tenant_%'"'"' ORDER BY 1"' 2>&1 | f
echo "=== table count in tenant_mirceatest (expect full set incl catalog) ==="
kubectl -n "$NS" exec "$PGPOD" -- sh -lc 'PGPASSWORD=$POSTGRES_PASSWORD psql -U $POSTGRES_USER -d $POSTGRES_DB -tAc "SELECT count(*) FROM information_schema.tables WHERE table_schema='"'"'tenant_mirceatest'"'"'"' 2>&1 | f
echo DONE
