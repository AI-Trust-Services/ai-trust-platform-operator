#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
kubectl -n "$NS" rollout restart deploy/shell 2>&1 | grep -avi memcache
kubectl -n "$NS" rollout status deploy/shell --timeout=120s 2>&1 | grep -avi memcache | tail -1
echo "=== confirm served luigi-config.js has relative viewUrls (no localhost) ==="
kubectl -n "$NS" exec deploy/shell -- sh -lc 'grep -c "localhost:8080" /usr/share/nginx/html/luigi-config.js 2>/dev/null; echo "relative viewUrls:"; grep -oE "viewUrl: \"/[a-z]+/" /usr/share/nginx/html/luigi-config.js 2>/dev/null | head' 2>&1 | grep -avi memcache | head -15
echo DONE
