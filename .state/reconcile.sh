#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
echo "=== shell image ref + full nginx conf (the DEPLOYED one) ==="
kubectl -n "$NS" get deploy shell -o jsonpath='{.spec.template.spec.containers[0].image}' 2>&1 | grep -avi memcache; echo
kubectl -n "$NS" exec deploy/shell -- sh -lc 'cat /etc/nginx/conf.d/default.conf 2>/dev/null || find /etc/nginx -name "*.conf" -exec cat {} \;' 2>&1 | grep -avi memcache | grep -iE 'X-Forwarded|X-Tenant|Authorization|location /api|X-Auth-Request' | head -60
echo
echo "=== registry backend image ref ==="
kubectl -n "$NS" get deploy ai-system-registry-backend -o jsonpath='{.spec.template.spec.containers[0].image}' 2>&1 | grep -avi memcache; echo
echo "=== does registry backend read X-Tenant-Id or tenant anywhere? (re-confirm) ==="
kubectl -n "$NS" exec deploy/ai-system-registry-backend -- sh -lc 'grep -rniE "x-tenant|tenant_id|current_tenant|tenancy" /app 2>/dev/null | grep -viE "[.]pyc" | head' 2>&1 | grep -avi memcache | head
echo "(empty above = backend has NO tenant code, only the shell nginx is tenancy-aware)"
echo DONE
