#!/bin/bash
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config
if ! kubectl --kubeconfig "$SHOOT_KUBECONFIG" get ns >/dev/null 2>&1; then echo "KUBECONFIG_EXPIRED"; exit 42; fi
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
f(){ grep -avi memcache; }
echo "=== roll operator v18 ==="
kubectl -n "$NS" set image deploy/aitrust-mt-operator operator="$OPERATOR_IMAGE:$OPERATOR_TAG" 2>&1 | f
kubectl -n "$NS" rollout status deploy/aitrust-mt-operator --timeout=120s 2>&1 | f | tail -1
echo "=== kill stuck jobs, re-stamp ==="
for o in livedemo mirceatest mttest2 sohan; do kubectl -n "$NS" delete job tenant-stores-$o --ignore-not-found 2>&1 | f; done
kubectl get subscriptions.sub.aitrustmt.msp -A -o jsonpath='{range .items[?(@.status.phase=="Ready")]}{.metadata.namespace}/{.metadata.name}{"\n"}{end}' 2>&1 | f | while read s; do
  [ -n "$s" ] && kubectl -n "${s%%/*}" annotate subscriptions.sub.aitrustmt.msp "${s##*/}" stage23=v18 --overwrite 2>&1 | f
done
echo "=== wait for 3-store jobs to COMPLETE ==="
for i in $(seq 1 18); do
  sleep 10
  DONE=$(kubectl -n "$NS" get jobs --no-headers 2>/dev/null | grep -avi memcache | grep -i tenant-stores | grep -cE 'Complete|1/1' || true)
  RUN=$(kubectl -n "$NS" get jobs --no-headers 2>/dev/null | grep -avi memcache | grep -i tenant-stores | grep -c Running || true)
  echo "  [$i] complete=$DONE running=$RUN"
  [ "$DONE" -ge 4 ] && break
done
kubectl -n "$NS" get jobs --no-headers 2>&1 | f | grep -i tenant-stores
echo "-- ch-migrate + minio-bucket logs (mirceatest) --"
kubectl -n "$NS" logs job/tenant-stores-mirceatest -c ch-migrate --tail=3 2>&1 | f | tail -3
kubectl -n "$NS" logs job/tenant-stores-mirceatest -c minio-bucket --tail=2 2>&1 | f | tail -2
echo DONE
