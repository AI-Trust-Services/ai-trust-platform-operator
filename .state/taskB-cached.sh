#!/bin/bash
# Task B — last-ditch: does the cached kcp-admin.kubeconfig reach anything WITHOUT a fresh shoot tunnel?
# (It points at the shoot's root-proxy via port-forward, so almost certainly no — confirm quickly, no hang.)
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh
load_config

echo "===== server URL in cached kcp-admin.kubeconfig ====="
grep -oE 'server: https://[^ ]+' "$STATE/kcp-admin.kubeconfig" 2>/dev/null | head -3

echo "===== is a root-proxy port-forward already running? ====="
pgrep -af 'port-forward.*6443' 2>&1 || echo "no port-forward running"

echo "===== try a 10s kubectl against cached kcp (expect fail — needs shoot tunnel) ====="
timeout 10 kubectl --kubeconfig "$STATE/kcp-admin.kubeconfig" get ns 2>&1 | head -5
echo "EXIT=${PIPESTATUS[0]}"
