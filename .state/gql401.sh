#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
echo "=== graphql-gateway recent auth errors (401 on root:orgs) ==="
kubectl -n platform-mesh-system logs deploy/kubernetes-graphql-gateway --since=10m 2>&1 | grep -av memcache | grep -iE '401|unauthor|token|root:orgs|forbidden|jwt|auth' | tail -15
echo "=== portal recent errors (token/oidc/gateway 401)? ==="
kubectl -n platform-mesh-system logs deploy/portal --since=10m 2>&1 | grep -av memcache | grep -iE '401|unauthor|token|gateway|oidc|error' | tail -12
echo "=== did the cert swap disturb anything? gateway/portal pod ages + restarts ==="
kubectl -n platform-mesh-system get pods 2>&1 | grep -av memcache | grep -E 'NAME|portal|graphql|iam|dex|keycloak'
echo "=== is this NEW (cert-related) or pre-existing? check if apex portal login (Dex/keycloak) works over the new cert ==="
kubectl -n platform-mesh-system get pods 2>&1 | grep -av memcache | grep -iE 'dex|keycloak|iam-service' | head
