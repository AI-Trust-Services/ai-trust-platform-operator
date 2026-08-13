#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config 2>&1 | tail -2
export KUBECONFIG="$SHOOT_KUBECONFIG"
echo "=== connectivity check ==="
kubectl get ns 2>&1 | grep -avi memcache | grep -iE 'platform-mesh|aitrust' | head
echo "--- pods in platform-mesh-system (idp-related) ---"
kubectl -n platform-mesh-system get pods 2>&1 | grep -avi memcache | grep -iE 'keycloak|iam|openfga|account|fga' | head -30
