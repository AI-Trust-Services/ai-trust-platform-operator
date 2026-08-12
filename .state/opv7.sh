#!/bin/bash
exec > /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP/.state/opv7.out 2>&1
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
rm -f "$SHOOT_KUBECONFIG"; mint_shoot_kubeconfig || { echo LOGIN_EXPIRED; exit 3; }
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS="${PROVIDER_NS:-aitrust-msp}"
DEP=$(kubectl -n "$NS" get deploy -o name 2>/dev/null | grep -i operator | head -1)
echo "DEP=$DEP"
kubectl -n "$NS" set image "$DEP" '*'=mirceacraciun795/aitrust-msp-operator:v7 2>&1 | grep -av memcache
kubectl -n "$NS" rollout status "$DEP" --timeout=120s 2>&1 | grep -av memcache | tail -1
echo "IMAGE_NOW=$(kubectl -n "$NS" get "$DEP" -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null)"
kubectl -n "$NS" get pods 2>/dev/null | grep -av memcache | grep -i operator
echo DONE
