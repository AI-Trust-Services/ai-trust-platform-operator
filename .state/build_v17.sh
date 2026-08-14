#!/bin/bash
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
echo "=== build+push ALL app images (CH lib/consumer + minio changes span many images) from mircea-mt2 HEAD ==="
bash scripts/2b-build-app-images.sh --skip-clone 2>&1 | tail -8
echo "APPS_EXIT: ${PIPESTATUS[0]}"
echo "=== build+push operator v17 ==="
bash scripts/2-build-operator-image.sh 2>&1 | tail -3
echo "OP_EXIT: ${PIPESTATUS[0]}"
