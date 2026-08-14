#!/bin/bash
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh 2>/dev/null; load_config 2>/dev/null
if [ -f "$SHOOT_KUBECONFIG" ] && kubectl --kubeconfig "$SHOOT_KUBECONFIG" get ns >/dev/null 2>&1; then
  echo "existing shoot kubeconfig still valid"; exit 0
fi
rm -f "$SHOOT_KUBECONFIG"
mint_shoot_kubeconfig 2>&1 | grep -avi memcache | tail -2
kubectl --kubeconfig "$SHOOT_KUBECONFIG" get ns >/dev/null 2>&1 && echo "MINT OK" || echo "MINT FAILED"
