#!/bin/bash
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config
SRC="$BUNDLE/../ai-trust-platform-git"
echo "===== 1) operator v10 (whitelist-domain + front-channel support) ====="
bash scripts/2-build-operator-image.sh 2>&1 | tail -3
echo "OP_EXIT: ${PIPESTATUS[0]}"
echo "===== 2) shell image (front-channel logout href) ====="
cd "$SRC"
docker build -q -t aitrust/shell:build ./shell >/dev/null && echo "  built shell"
docker tag aitrust/shell:build "$REGISTRY/aitrust-shell:$TAG"
docker push -q "$REGISTRY/aitrust-shell:$TAG" && echo "  pushed $REGISTRY/aitrust-shell:$TAG"
echo "ALLDONE_V10"
