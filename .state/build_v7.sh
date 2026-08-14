#!/bin/bash
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
echo "===== 1) build+push OPERATOR (v7, embeds updated manifests/*.tmpl) ====="
bash scripts/2-build-operator-image.sh 2>&1 | tail -8
echo "OPERATOR EXIT: ${PIPESTATUS[0]}"

echo "===== 2) build+push users-backend from mircea-mt2 HEAD (--skip-clone: no reset, keeps tenancy code) ====="
echo "  building from $(git -C ../ai-trust-platform-git rev-parse --abbrev-ref HEAD) @ $(git -C ../ai-trust-platform-git rev-parse --short HEAD)"
# Build just users-backend (not the whole 2b) to save time — reuse 2b's exact build+push for that one image.
source scripts/lib.sh; load_config
SRC="$BUNDLE/../ai-trust-platform-git"
cd "$SRC"
docker build -q -t aitrust/users-backend:build -f users/backend/Dockerfile . >/dev/null && echo "  built users-backend"
docker tag aitrust/users-backend:build "$REGISTRY/aitrust-users-backend:$TAG"
docker push -q "$REGISTRY/aitrust-users-backend:$TAG" && echo "  pushed $REGISTRY/aitrust-users-backend:$TAG"
echo "ALLDONE"
