#!/bin/bash
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh 2>/dev/null; load_config 2>/dev/null
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
f(){ grep -avi memcache; }
echo "=== served luigi-config.js: post-logout target line ==="
kubectl -n "$NS" exec deploy/shell -- sh -c 'grep -n "oauth2/start\|postLogout\|post_logout_redirect_uri" /usr/share/nginx/html/luigi-config.js 2>/dev/null | head' 2>&1 | f
