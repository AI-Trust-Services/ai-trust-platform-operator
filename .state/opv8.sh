#!/bin/bash
exec > /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP/.state/opv8.out 2>&1
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
kubectl get ns >/dev/null 2>&1 || { echo LOGIN_EXPIRED; exit 3; }
NS="${PROVIDER_NS:-aitrust-msp}"
DEP=$(kubectl -n "$NS" get deploy -o name 2>/dev/null | grep -avi memcache | grep -i operator | head -1)
echo "DEP=$DEP"
kubectl -n "$NS" set image "$DEP" '*'=mirceacraciun795/aitrust-msp-operator:v8 2>&1 | grep -avi memcache
kubectl -n "$NS" rollout status "$DEP" --timeout=120s 2>&1 | grep -avi memcache | tail -1
echo "IMAGE_NOW=$(kubectl -n "$NS" get "$DEP" -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null)"
echo DONE
