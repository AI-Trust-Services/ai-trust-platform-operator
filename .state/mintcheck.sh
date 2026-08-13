#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config
echo "STATE=$STATE"
echo "SHOOT_KUBECONFIG=$SHOOT_KUBECONFIG"
rm -f "$SHOOT_KUBECONFIG"; mint_shoot_kubeconfig 2>&1 | grep -avi memcache | tail -1
echo "after mint, file size: $(wc -c < "$SHOOT_KUBECONFIG" 2>/dev/null || echo MISSING)"
kubectl --kubeconfig "$SHOOT_KUBECONFIG" get ns aitrust-mt-msp -o jsonpath='{.status.phase}{"\n"}' 2>&1 | grep -avi memcache
