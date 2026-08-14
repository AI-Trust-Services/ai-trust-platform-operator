#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
echo "=== TENANCY_MODE: where is it set? (deploy env + app-config CM) ==="
kubectl -n "$NS" get deploy ai-system-registry-backend -o jsonpath='{range .spec.template.spec.containers[0].envFrom[*]}envFrom cm={.configMapRef.name}{"\n"}{end}' 2>&1 | grep -avi memcache
kubectl -n "$NS" get deploy ai-system-registry-backend -o jsonpath='{range .spec.template.spec.containers[0].env[?(@.name=="TENANCY_MODE")]}TENANCY_MODE(env)={.value}{"\n"}{end}' 2>&1 | grep -avi memcache
echo "--- app-config CM values ---"
kubectl -n "$NS" get cm app-config -o jsonpath='{.data.TENANCY_MODE}{"|"}{.data.TENANT_CLAIM}{"\n"}' 2>&1 | grep -avi memcache
echo "--- what the process actually sees (from /proc/1/environ) ---"
kubectl -n "$NS" exec deploy/ai-system-registry-backend -- sh -lc 'tr "\0" "\n" < /proc/1/environ | grep -iE "^TENANCY_MODE=|^TENANT_CLAIM=|^TENANCY_JWKS"' 2>&1 | grep -avi memcache
echo "=== shell nginx serves the new security headers? (from shell pod directly) ==="
kubectl -n "$NS" exec deploy/shell -- sh -lc 'grep -iE "Content-Security-Policy|Strict-Transport|X-Content-Type|Referrer-Policy|X-Frame-Options|Allow-Origin" /etc/nginx/conf.d/default.conf 2>/dev/null || grep -iE "Content-Security-Policy|Strict-Transport|X-Content-Type|Referrer-Policy|X-Frame-Options|Allow-Origin" /etc/nginx/nginx.conf' 2>&1 | grep -avi memcache | head
echo DONE
