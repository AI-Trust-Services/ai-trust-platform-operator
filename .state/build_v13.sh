#!/bin/bash
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config
SRC="$BUNDLE/../ai-trust-platform-git"

echo "===== 1) rebuild db-migrate image (has updated env.py TARGET_SCHEMA support) ====="
cd "$SRC"
docker build -q -t aitrust/db-migrate:build ./libs/persistence >/dev/null && echo "  built db-migrate"
docker tag aitrust/db-migrate:build "$REGISTRY/aitrust-db-migrate:$TAG"
docker push -q "$REGISTRY/aitrust-db-migrate:$TAG" && echo "  pushed $REGISTRY/aitrust-db-migrate:$TAG"

echo "===== 2) build+push operator v13 (compiles guard + tenant-stores step) ====="
cd "$BUNDLE"
bash scripts/2-build-operator-image.sh 2>&1 | tail -5
echo "OP_EXIT: ${PIPESTATUS[0]}"
