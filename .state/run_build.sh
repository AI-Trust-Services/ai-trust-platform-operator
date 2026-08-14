#!/bin/bash
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
# Build ALL MT app images from the CURRENT working tree (branch mircea-mt2, has libs/tenancy).
# --skip-clone => do NOT fetch/reset to origin/main (which would destroy the 7 unpushed tenancy commits
# AND ship images without multi-tenancy). Build from HEAD as-is.
echo "=== building from $(git -C ../ai-trust-platform-git rev-parse --abbrev-ref HEAD) @ $(git -C ../ai-trust-platform-git rev-parse --short HEAD) ==="
bash scripts/2b-build-app-images.sh --skip-clone 2>&1
echo "=== BUILD SCRIPT EXIT: $? ==="