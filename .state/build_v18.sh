#!/bin/bash
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config
bash scripts/2-build-operator-image.sh 2>&1 | tail -3
echo "OP_EXIT: ${PIPESTATUS[0]}"
