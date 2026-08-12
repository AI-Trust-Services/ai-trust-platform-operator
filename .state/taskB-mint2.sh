#!/bin/bash
# Task B — retry mint WITHOUT the timeout wrapper (timeout not on PATH in prior run).
# Use bash read-timeout via background+kill guard instead.
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh
load_config

which timeout 2>&1 || echo "no timeout binary"

echo "===== raw adminkubeconfig request (background+guard) ====="
(
  garden create -f - --raw \
    "/apis/core.gardener.cloud/v1beta1/namespaces/${PROJECT}/shoots/${SHOOT_NAME}/adminkubeconfig" <<< \
    '{"apiVersion":"authentication.gardener.cloud/v1alpha1","kind":"AdminKubeconfigRequest","spec":{"expirationSeconds":14400}}' \
    > "$STATE/mint-resp.json" 2>"$STATE/mint-err.txt"
  echo "GARDEN_EXIT=$?" > "$STATE/mint-exit.txt"
) &
GPID=$!
# guard: wait up to 35s
for i in $(seq 1 35); do
  kill -0 $GPID 2>/dev/null || break
  sleep 1
done
if kill -0 $GPID 2>/dev/null; then
  kill $GPID 2>/dev/null
  echo "RESULT: garden call HUNG >35s (interactive OIDC prompt) — garden login expired, needs prerequisites/login.sh"
  exit 7
fi
echo "--- mint-exit ---"; cat "$STATE/mint-exit.txt" 2>/dev/null
echo "--- mint-err (first 15) ---"; head -15 "$STATE/mint-err.txt" 2>/dev/null
echo "--- mint-resp status ---"
if head -c1 "$STATE/mint-resp.json" 2>/dev/null | grep -q '{'; then
  cat "$STATE/mint-resp.json" | jq -r '.status.kubeconfig' 2>/dev/null | head -c 20 | sed 's/./x/g'
  echo " (got kubeconfig bytes)"
  cat "$STATE/mint-resp.json" | jq -r '.status.kubeconfig' | base64 -d > "$SHOOT_KUBECONFIG" 2>/dev/null
  echo "SHOOT_KUBECONFIG written: $([ -s "$SHOOT_KUBECONFIG" ] && echo yes || echo empty)"
else
  echo "no JSON body"
fi
