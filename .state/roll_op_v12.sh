#!/bin/bash
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
f(){ grep -avi memcache; }
echo "=== roll operator to v12 ==="
kubectl -n "$NS" set image deploy/aitrust-mt-operator operator="$OPERATOR_IMAGE:$OPERATOR_TAG" 2>&1 | f
kubectl -n "$NS" rollout status deploy/aitrust-mt-operator --timeout=120s 2>&1 | f | tail -1
kubectl -n "$NS" logs deploy/aitrust-mt-operator --tail=12 2>&1 | f | grep -iE 'v12 starting' | tail -1
echo "=== dump current live pm-content.json to a file for editing ==="
kubectl -n "$NS" get configmap aitrust-mt-portal-config -o jsonpath='{.data.pm-content\.json}' 2>/dev/null | grep -avi memcache > .state/pm-content.live.json
echo "  bytes: $(wc -c < .state/pm-content.live.json)"
echo "  Plan field present? $(grep -c '\"Plan\"' .state/pm-content.live.json)"
echo DONE
