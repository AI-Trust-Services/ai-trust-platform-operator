#!/bin/bash
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
f(){ grep -avi memcache; }

echo "=== roll operator v15 ==="
kubectl -n "$NS" set image deploy/aitrust-mt-operator operator="$OPERATOR_IMAGE:$OPERATOR_TAG" 2>&1 | f
kubectl -n "$NS" rollout status deploy/aitrust-mt-operator --timeout=120s 2>&1 | f | tail -1

echo "=== roll all backends (pick up SET ROLE session hook) ==="
for d in $(kubectl -n "$NS" get deploy -o name 2>/dev/null | grep -avi memcache | grep -E 'backend|shell'); do
  kubectl -n "$NS" rollout restart "$d" 2>&1 | f
done

echo "=== wait for tenant-stores jobs (role model) to complete ==="
for i in $(seq 1 15); do
  sleep 10
  RUN=$(kubectl -n "$NS" get jobs --no-headers 2>/dev/null | grep -avi memcache | grep -i tenant-stores | grep -c Running || true)
  echo "  [$i] tenant-stores running=$RUN"
  [ "$RUN" = "0" ] && break
done
kubectl -n "$NS" get jobs --no-headers 2>&1 | f | grep -i tenant-stores
echo "-- one job log --"
kubectl -n "$NS" logs job/tenant-stores-mirceatest --tail=6 2>&1 | f | grep -iE 'provisioned role|done|error' | tail -4
echo DONE
