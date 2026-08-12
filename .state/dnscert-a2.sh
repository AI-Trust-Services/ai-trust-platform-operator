#!/bin/bash
# TASK A probe #2 — can we reach the garden API at all? (READ-ONLY, bounded)
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh
load_config

echo "=== garden kubeconfig server + whoami (bounded 25s) ==="
grep -E "server:" "$GARDEN_KUBECONFIG" 2>&1 | head -3
echo "---"
timeout 25 bash -c 'source scripts/lib.sh; load_config; garden get shoot '"$SHOOT_NAME"' -n '"$PROJECT"' -o jsonpath="{.status.lastOperation.state}{\"\\n\"}"' 2>&1
RC=$?
echo "garden-get rc=$RC"
if [ $RC -eq 124 ]; then echo "GARDEN_LOGIN_EXPIRED (interactive OIDC prompt) — needs prerequisites/login.sh"; fi
echo
echo "=== any cached admin token in garden-kubeconfig? (exec-plugin vs token) ==="
grep -E "exec:|command:|token:|client-certificate|oidc-login|kubectl-oidc" "$GARDEN_KUBECONFIG" 2>&1 | sed -E 's/(token:).*/\1 <redacted>/' | head -20
