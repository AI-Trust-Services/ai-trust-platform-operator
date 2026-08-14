#!/bin/bash
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh 2>/dev/null; load_config 2>/dev/null
echo "REGISTRY=$REGISTRY  TAG=$TAG"
echo "SHARED_APP_HOST=$SHARED_APP_HOST"
echo "PROVIDER_NS=$PROVIDER_NS"
echo "--- docker present? ---"
docker version --format '  client={{.Client.Version}} server={{.Server.Version}}' 2>&1 | head -3 || echo "  docker NOT available in WSL"
echo "--- logged into registry? (push target $REGISTRY) ---"
docker info 2>/dev/null | grep -i username || echo "  (no username in docker info — may still be logged in via credstore)"
echo "--- git clone dir present? ---"
ls -d "$BUNDLE/../ai-trust-platform-git/.git" 2>/dev/null && echo "  clone exists (will fetch/reset to main)" || echo "  no clone yet (will clone)"
echo DONE