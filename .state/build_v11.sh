#!/bin/bash
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
bash scripts/2-build-operator-image.sh 2>&1 | tail -3
echo "OP_EXIT: ${PIPESTATUS[0]}"
kubectl -n aitrust-mt-msp set image deploy/aitrust-mt-operator operator="$OPERATOR_IMAGE:$OPERATOR_TAG" 2>&1 | grep -avi memcache
kubectl -n aitrust-mt-msp rollout status deploy/aitrust-mt-operator --timeout=120s 2>&1 | grep -avi memcache | tail -1
echo "V11_ROLLED"
