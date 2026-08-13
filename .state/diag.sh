#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
echo "=== all pods in aitrust-mt-msp ==="
kubectl -n aitrust-mt-msp get pods 2>&1 | grep -avi memcache
echo "=== jobs in aitrust-mt-msp ==="
kubectl -n aitrust-mt-msp get jobs 2>&1 | grep -avi memcache
echo "=== the MT operator pod + its recent logs (why Subscription not Ready?) ==="
kubectl -n aitrust-mt-msp get pods -l app.kubernetes.io/name=aitrust-mt-operator 2>&1 | grep -avi memcache
kubectl -n aitrust-mt-msp logs deploy/aitrust-mt-operator --tail=30 2>&1 | grep -avi memcache | tail -30
echo "=== keycloak deploy status (provision job depends on it) ==="
kubectl -n aitrust-mt-msp get deploy keycloak 2>&1 | grep -avi memcache
echo "=== Subscription mirror on the shoot ==="
kubectl get subscriptions.sub.aitrustmt.msp -A 2>&1 | grep -avi memcache | head
