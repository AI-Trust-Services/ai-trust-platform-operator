#!/bin/bash
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
f(){ grep -avi memcache; }
echo "=== roll operator to v14 ==="
kubectl -n "$NS" set image deploy/aitrust-mt-operator operator="$OPERATOR_IMAGE:$OPERATOR_TAG" 2>&1 | f
kubectl -n "$NS" rollout status deploy/aitrust-mt-operator --timeout=120s 2>&1 | f | tail -1
echo "=== wait for tenant-stores jobs to complete (up to ~2.5m) ==="
for i in $(seq 1 15); do
  sleep 10
  DONE=$(kubectl -n "$NS" get jobs --no-headers 2>/dev/null | grep -avi memcache | grep -i tenant-stores | grep -cE 'Complete|1/1' || true)
  RUN=$(kubectl -n "$NS" get jobs --no-headers 2>/dev/null | grep -avi memcache | grep -i tenant-stores | grep -c Running || true)
  echo "  [$i] complete=$DONE running=$RUN"
  [ "$RUN" = "0" ] && [ "$DONE" != "0" ] && break
done
echo "-- job statuses --"; kubectl -n "$NS" get jobs --no-headers 2>&1 | f | grep -i tenant-stores
echo; echo "=== subscription phases (expect real orgs Ready) ==="
kubectl get subscriptions.sub.aitrustmt.msp -A -o jsonpath='{range .items[*]}{.spec.org}={.status.phase}{"\n"}{end}' 2>&1 | f | grep -vE '^=' | sort -u
echo DONE
