#!/bin/bash
# Task B — diagnose WHY mint failed: is garden token expired, or is it a transient/network issue?
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh
load_config

echo "===== garden-kubeconfig.yaml present? ====="
ls -la "$PREREQ/garden-kubeconfig.yaml" 2>&1 || echo "MISSING"

echo "===== any cached shoot/kcp kubeconfig in .state? ====="
ls -la "$STATE"/*kubeconfig* 2>&1 || echo "none"

echo "===== raw adminkubeconfig request (30s timeout, show error) ====="
timeout 30 garden create -f - --raw \
  "/apis/core.gardener.cloud/v1beta1/namespaces/${PROJECT}/shoots/${SHOOT_NAME}/adminkubeconfig" <<< \
  '{"apiVersion":"authentication.gardener.cloud/v1alpha1","kind":"AdminKubeconfigRequest","spec":{"expirationSeconds":14400}}' \
  2>&1 | head -20
echo "EXIT=$?"

echo "===== can we even reach garden apiserver (get shoot)? ====="
timeout 25 garden -n "$PROJECT" get shoot "$SHOOT_NAME" 2>&1 | head -10
echo "EXIT=$?"
