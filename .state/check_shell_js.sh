#!/bin/bash
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh 2>/dev/null; load_config 2>/dev/null
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
f(){ grep -avi memcache; }
echo "=== shell pod age + image ==="
kubectl -n "$NS" get pods -l app=shell --no-headers 2>&1 | f
kubectl -n "$NS" get deploy shell -o jsonpath='image={.spec.template.spec.containers[0].image}  pullPolicy={.spec.template.spec.containers[0].imagePullPolicy}{"\n"}' 2>&1 | f
echo "=== does the SERVED luigi-config.js have the front-channel logout code? ==="
kubectl -n "$NS" exec deploy/shell -- sh -c 'grep -c "sign_out?rd=\|post_logout_redirect_uri\|ai-trust-mt-" /usr/share/nginx/html/luigi-config.js 2>/dev/null' 2>&1 | f
echo "=== show the actual sign-out href line served ==="
kubectl -n "$NS" exec deploy/shell -- sh -c 'grep -n "sign_out\|btn.href\|kcLogout" /usr/share/nginx/html/luigi-config.js 2>/dev/null | head' 2>&1 | f
