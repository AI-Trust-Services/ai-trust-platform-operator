#!/bin/bash
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
f(){ grep -avi memcache; }

echo "=== roll operator to v13 ==="
kubectl -n "$NS" set image deploy/aitrust-mt-operator operator="$OPERATOR_IMAGE:$OPERATOR_TAG" 2>&1 | f
kubectl -n "$NS" rollout status deploy/aitrust-mt-operator --timeout=120s 2>&1 | f | tail -1
kubectl -n "$NS" logs deploy/aitrust-mt-operator --tail=8 2>&1 | f | grep -iE 'v13 starting' | tail -1

echo "=== watch tenant-stores jobs appear (operator reconciles all subs) ==="
sleep 25
echo "-- tenant-stores jobs --"
kubectl -n "$NS" get jobs -l app.kubernetes.io/managed-by=aitrust-mt-operator --no-headers 2>&1 | f | grep -i tenant-stores || echo "  (none yet)"
echo "-- subscription phases now (some may be Provisioning transiently) --"
kubectl get subscriptions.sub.aitrustmt.msp -A -o jsonpath='{range .items[*]}{.spec.org}={.status.phase}{"\n"}{end}' 2>&1 | f | grep -vE '^=' | sort | uniq -c
echo DONE
