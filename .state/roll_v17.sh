#!/bin/bash
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config
# kubeconfig may have expired during the long build — re-mint if needed
kubectl --kubeconfig "$SHOOT_KUBECONFIG" get ns >/dev/null 2>&1 || { echo "KUBECONFIG EXPIRED"; exit 42; }
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
f(){ grep -avi memcache; }
echo "=== roll operator v17 ==="
kubectl -n "$NS" set image deploy/aitrust-mt-operator operator="$OPERATOR_IMAGE:$OPERATOR_TAG" 2>&1 | f
kubectl -n "$NS" rollout status deploy/aitrust-mt-operator --timeout=120s 2>&1 | f | tail -1
echo "=== roll CH consumer + all backends + compliance (new CH/MinIO code) ==="
for d in clickhouse-consumer compliance-backend monitoring-backend alerts-backend decision-trace-analyzer-backend policy-checker-worker; do
  kubectl -n "$NS" rollout restart deploy/$d 2>&1 | f || true
done
echo "=== delete tenant-stores jobs so v17 re-stamps with CH+MinIO steps ==="
for o in livedemo mirceatest mttest2 sohan; do kubectl -n "$NS" delete job tenant-stores-$o --ignore-not-found 2>&1 | f; done
echo "=== nudge Ready subs to reconcile ==="
kubectl get subscriptions.sub.aitrustmt.msp -A -o jsonpath='{range .items[?(@.status.phase=="Ready")]}{.metadata.namespace}/{.metadata.name}{"\n"}{end}' 2>&1 | f | while read s; do
  [ -n "$s" ] && kubectl -n "${s%%/*}" annotate subscriptions.sub.aitrustmt.msp "${s##*/}" stage23=v17 --overwrite 2>&1 | f
done
echo "=== wait for tenant-stores jobs (3-store) to complete ==="
for i in $(seq 1 18); do
  sleep 10
  N=$(kubectl -n "$NS" get jobs --no-headers 2>/dev/null | grep -avi memcache | grep -ci tenant-stores || true)
  RUN=$(kubectl -n "$NS" get jobs --no-headers 2>/dev/null | grep -avi memcache | grep -i tenant-stores | grep -c Running || true)
  echo "  [$i] tenant-stores total=$N running=$RUN"
  [ "$N" != "0" ] && [ "$RUN" = "0" ] && break
done
kubectl -n "$NS" get jobs --no-headers 2>&1 | f | grep -i tenant-stores
echo "-- one job's init container logs (ch-migrate + minio-bucket) --"
kubectl -n "$NS" logs job/tenant-stores-mirceatest -c ch-migrate --tail=4 2>&1 | f | tail -4
kubectl -n "$NS" logs job/tenant-stores-mirceatest -c minio-bucket --tail=3 2>&1 | f | tail -3
echo DONE
