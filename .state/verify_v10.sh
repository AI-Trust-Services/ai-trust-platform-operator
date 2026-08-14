#!/bin/bash
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh 2>/dev/null; load_config 2>/dev/null
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
f(){ grep -avi memcache; }

echo "===== shell serves the front-channel logout JS? (grep the served luigi-config.js) ====="
kubectl -n "$NS" exec deploy/shell -- sh -c 'grep -o "oauth2/sign_out?rd=\|ai-trust-mt-.*org\|post_logout_redirect_uri" /usr/share/nginx/html/luigi-config.js 2>/dev/null | head -3' 2>&1 | f || echo "  (grep found nothing — check path)"

echo; echo "===== fridaytest proxy: exact whitelist-domain + backend-logout args ====="
kubectl -n "$NS" get deploy oauth2-proxy-fridaytest -o jsonpath='{range .spec.template.spec.containers[0].args[*]}{@}{"\n"}{end}' 2>&1 | f | grep -iE 'whitelist|backend-logout'

echo; echo "===== kc-client-fridaytest job (post-logout attr re-applied clean?) ====="
kubectl -n "$NS" get job kc-client-fridaytest --no-headers 2>&1 | f
kubectl -n "$NS" logs job/kc-client-fridaytest --tail=4 2>&1 | f | tail -4
echo DONE
