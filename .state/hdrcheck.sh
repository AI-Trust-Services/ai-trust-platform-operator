#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
echo "=== oauth2-proxy args: which pass-* flags are set? ==="
kubectl -n "$NS" get deploy oauth2-proxy -o jsonpath='{range .spec.template.spec.containers[0].args[*]}{@}{"\n"}{end}' 2>&1 | grep -avi memcache | grep -iE 'pass-|set-xauth|set-auth|prefer-email|skip-jwt'
echo
echo "NOTE: oauth2-proxy v7.6.0 header behavior (reference):"
echo " - --pass-access-token=true  -> sets X-Forwarded-Access-Token (the ACCESS token JWT) to upstream"
echo " - --set-xauthrequest=true   -> sets X-Auth-Request-{User,Email,Preferred-Username,Access-Token} (for nginx auth_request; also passed upstream in reverse-proxy)"
echo " - --pass-authorization-header=true -> sets Authorization: Bearer <ID token>"
echo " - --pass-user-headers=true (DEFAULT) -> X-Forwarded-{User,Email,Preferred-Username,Groups}"
echo
echo "=== current shell nginx: which headers does it forward to /api/registry? ==="
kubectl -n "$NS" exec deploy/shell -- sh -lc 'cat /etc/nginx/conf.d/default.conf 2>/dev/null || cat /etc/nginx/nginx.conf 2>/dev/null' 2>&1 | grep -avi memcache | grep -iE 'location /api|proxy_set_header|proxy_pass' | head -40
echo DONE
