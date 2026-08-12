#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
[ -s "$SHOOT_KUBECONFIG" ] || mint_shoot_kubeconfig >/dev/null 2>&1
NS="${PROVIDER_NS:-aitrust-msp}"
echo "OPERATOR_IMAGE_NOW:"
kubectl -n "$NS" get deploy -o jsonpath='{range .items[*]}{.metadata.name}{"  "}{.spec.template.spec.containers[0].image}{"\n"}{end}' 2>&1 | grep -av memcache | grep -i operator
echo "OPERATOR_PODS:"
kubectl -n "$NS" get pods 2>&1 | grep -av memcache | grep -i operator
