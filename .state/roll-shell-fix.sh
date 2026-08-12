#!/bin/bash
# Roll the fixed shell (relative viewUrls) across every live instance + the standalone app.
# Patches shell imagePullPolicy->Always (forces a fresh pull of the overwritten :aitrust-1 digest),
# then waits for each rollout. Finally verifies the served luigi-config has RELATIVE viewUrls.
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
rm -f "$SHOOT_KUBECONFIG"; mint_shoot_kubeconfig >/dev/null 2>&1 || { echo LOGIN_EXPIRED; exit 3; }
export KUBECONFIG="$SHOOT_KUBECONFIG"

echo "=== discovering shell deployments (aitp-* instances + standalone ai-trust-app) ==="
NSS=$(kubectl get ns -o name 2>/dev/null | grep -av memcache | grep -oE 'aitp-[a-z0-9-]+')
NSS="$NSS ai-trust-app"
for ns in $NSS; do
  kubectl -n "$ns" get deploy shell >/dev/null 2>&1 || { echo "  (skip $ns: no shell)"; continue; }
  echo "-- $ns --"
  kubectl -n "$ns" patch deploy shell --type=json \
    -p '[{"op":"replace","path":"/spec/template/spec/containers/0/imagePullPolicy","value":"Always"}]' 2>&1 | grep -av memcache
  kubectl -n "$ns" rollout restart deploy/shell 2>&1 | grep -av memcache
done
echo "=== waiting for rollouts ==="
for ns in $NSS; do
  kubectl -n "$ns" get deploy shell >/dev/null 2>&1 || continue
  kubectl -n "$ns" rollout status deploy/shell --timeout=150s 2>&1 | grep -av memcache | tail -1
done
echo "=== VERIFY: served luigi-config viewUrls are RELATIVE (no ai-trust-platform-main, no http://) ==="
for ns in $NSS; do
  kubectl -n "$ns" get deploy shell >/dev/null 2>&1 || continue
  echo "-- $ns --"
  kubectl -n "$ns" exec deploy/shell -- cat /usr/share/nginx/html/luigi-config.js 2>/dev/null \
    | grep -av memcache | grep -E 'viewUrl' | head -3
done
