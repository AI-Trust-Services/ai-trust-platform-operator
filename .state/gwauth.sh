#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
echo "=== gateway: the EXACT 401 reason for root:orgs (token missing? expired? bad audience/issuer?) ==="
kubectl -n platform-mesh-system logs deploy/kubernetes-graphql-gateway --since=8m 2>&1 | grep -av memcache \
  | grep -iE 'root:orgs|401|unauth|token|audience|issuer|jwt|verif|expired|bearer' | tail -20
echo "=== how does the gateway authenticate requests? its auth/oidc config ==="
kubectl -n platform-mesh-system get deploy kubernetes-graphql-gateway -o jsonpath='{range .spec.template.spec.containers[0].env[*]}{.name}={.value}{"\n"}{end}' 2>&1 | grep -av memcache | grep -iE 'OIDC|ISSUER|AUDIENCE|AUTH|JWK|TOKEN|IAM' | grep -ivE 'SECRET' | head
echo "=== the portal 'welcome' client expected audience vs what the gateway wants ==="
kubectl -n platform-mesh-system logs deploy/portal --since=8m 2>&1 | grep -av memcache | grep -iE 'audience|issuer|token|welcome|401|discovery' | tail -8
