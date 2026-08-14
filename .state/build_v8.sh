#!/bin/bash
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
echo "=== stop the crashlooping v7 kc-client-fridaytest job (old broken template) ==="
kubectl -n aitrust-mt-msp delete job kc-client-fridaytest --ignore-not-found 2>&1 | grep -avi memcache
echo "=== build+push operator v8 (fixed id extraction + PUT error handling) ==="
bash scripts/2-build-operator-image.sh 2>&1 | tail -6
echo "BUILD_V8_EXIT: ${PIPESTATUS[0]}"
