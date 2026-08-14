#!/bin/bash
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
f(){ grep -avi memcache; }

echo "=== confirm operator is actually v15 (startup log) ==="
kubectl -n "$NS" logs deploy/aitrust-mt-operator 2>&1 | f | grep -iE 'aitrust-mt-operator v1[0-9] starting' | tail -1

echo "=== clean: drop stale direct grants on tenant schemas from ai_trust_app (v14 leftover) ==="
PGPOD=$(kubectl -n "$NS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep -E '^postgres' | awk '{print $1}' | head -1)
kubectl -n "$NS" exec "$PGPOD" -- sh -lc 'PGPASSWORD=$POSTGRES_PASSWORD psql -U $POSTGRES_USER -d $POSTGRES_DB <<SQL 2>&1
REVOKE ALL ON SCHEMA tenant_livedemo, tenant_mirceatest, tenant_mttest2, tenant_sohan FROM ai_trust_app;
SQL' 2>&1 | f

echo "=== delete ALL tenant-stores jobs so v15 re-stamps fresh ==="
kubectl -n "$NS" delete job -l app.kubernetes.io/managed-by=aitrust-mt-operator 2>&1 | f | grep -i tenant-stores || true
for o in livedemo mirceatest mttest2 sohan; do kubectl -n "$NS" delete job tenant-stores-$o --ignore-not-found 2>&1 | f; done

echo "=== nudge subscriptions to reconcile (bump annotation) ==="
kubectl get subscriptions.sub.aitrustmt.msp -A -o jsonpath='{range .items[?(@.status.phase=="Ready")]}{.metadata.namespace}/{.metadata.name}{"\n"}{end}' 2>&1 | f | while read s; do
  [ -n "$s" ] && kubectl -n "${s%%/*}" annotate subscriptions.sub.aitrustmt.msp "${s##*/}" reprovision=v15 --overwrite 2>&1 | f
done

echo "=== wait for fresh jobs + check the NEW log message ==="
for i in $(seq 1 12); do
  sleep 10
  RUN=$(kubectl -n "$NS" get jobs --no-headers 2>/dev/null | grep -avi memcache | grep -i tenant-stores | grep -c Running || true)
  N=$(kubectl -n "$NS" get jobs --no-headers 2>/dev/null | grep -avi memcache | grep -ci tenant-stores || true)
  echo "  [$i] tenant-stores total=$N running=$RUN"
  [ "$N" != "0" ] && [ "$RUN" = "0" ] && break
done
kubectl -n "$NS" get jobs --no-headers 2>&1 | f | grep -i tenant-stores
echo "-- NEW job log (expect 'provisioned role t_mirceatest') --"
kubectl -n "$NS" logs job/tenant-stores-mirceatest 2>&1 | f | grep -iE 'provisioned role|granted|error|denied' | tail -5
echo DONE
