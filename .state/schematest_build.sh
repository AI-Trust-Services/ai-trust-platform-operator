#!/bin/bash
set -euo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh
load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"

APP_REPO="$BUNDLE/../ai-trust-platform-git"
echo "REGISTRY=$REGISTRY TAG=$TAG"
echo "Building db-migrate image from $APP_REPO/libs/persistence ..."
docker build -q -t aitrust/db-migrate:build "$APP_REPO/libs/persistence"
docker tag aitrust/db-migrate:build "$REGISTRY/aitrust-db-migrate:$TAG"
docker push "$REGISTRY/aitrust-db-migrate:$TAG"
echo "PUSH_DONE $REGISTRY/aitrust-db-migrate:$TAG"
