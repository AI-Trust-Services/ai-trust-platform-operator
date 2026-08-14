#!/bin/bash
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh 2>/dev/null; load_config 2>/dev/null
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
f(){ grep -avi memcache; }
echo "=== live portal ConfigMap: is it managed by helm? (annotations) ==="
kubectl -n "$NS" get configmap aitrust-mt-portal-config -o jsonpath='{.metadata.annotations}{"\n"}' 2>&1 | f | head -c 400; echo
echo "=== does the live form still have the Plan + Org fields? ==="
kubectl -n "$NS" get configmap aitrust-mt-portal-config -o jsonpath='{.data.pm-content\.json}' 2>&1 | f | grep -oE '"label": "[^"]*"' | head -20
echo "=== portal-integration pod ==="
kubectl -n "$NS" get pods -l app.kubernetes.io/component=portal-integration --no-headers 2>&1 | f
