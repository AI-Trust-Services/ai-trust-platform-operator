#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
echo "=== portal OIDC/issuer config (does it point at the apex host over https?) ==="
kubectl -n platform-mesh-system get deploy portal -o jsonpath='{range .spec.template.spec.containers[0].env[*]}{.name}={.value}{"\n"}{end}' 2>&1 | grep -av memcache | grep -iE 'ISSUER|OIDC|AUTH|IDP|DEX|KEYCLOAK|URL|CLIENT' | grep -ivE 'SECRET' | head -20
echo "=== dex recent logs — is it issuing tokens / any error over the new cert? ==="
kubectl -n platform-mesh-system logs deploy/dex --since=15m 2>&1 | grep -av memcache | grep -iE 'error|token|approval|callback|refused|tls|x509' | tail -10
echo "=== iam-service recent errors ==="
kubectl -n platform-mesh-system logs deploy/iam-service --since=15m 2>&1 | grep -av memcache | grep -iE 'error|401|token|unauthor' | tail -8
echo "=== was the portal auth ALREADY warning about no refresh token BEFORE the cert swap? check older logs ==="
kubectl -n platform-mesh-system logs deploy/portal --since=6h 2>&1 | grep -av memcache | grep -c 'No refresh token present'
echo "  ^ count of 'No refresh token' over 6h (if high + constant, it's a normal 'not logged in yet' warning, not new)"
