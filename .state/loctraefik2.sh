#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
echo "=== LoadBalancer svcs ==="
kubectl get svc -A 2>&1 | grep -av memcache | awk 'NR==1 || /LoadBalancer/'
echo "=== deploy/ds with traefik in name (all ns) ==="
kubectl get deploy,ds -A 2>&1 | grep -av memcache | grep -iE 'traefik|NAME'
echo "=== pods by traefik image ==="
kubectl get pods -A -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name} {.spec.containers[0].image}{"\n"}{end}' 2>&1 | grep -av memcache | grep -iE 'traefik' | head
