#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
echo "=== does the testai namespace still exist? state? ==="
kubectl get ns aitp-33hins0iklcwfg45-testai 2>&1 | grep -av memcache
echo "=== ALL aitp-* namespaces (are the other instances alive?) ==="
kubectl get ns 2>&1 | grep -av memcache | grep -E 'aitp-|NAME'
echo "=== pods in testai ns (any state incl terminating) ==="
kubectl get pods -n aitp-33hins0iklcwfg45-testai 2>&1 | grep -av memcache | head
echo "=== msp-at-big node health (did the node go down?) ==="
kubectl get nodes 2>&1 | grep -av memcache | grep -E 'NAME|msp-at-big'
echo "=== can we even reach the API server / is this a kubeconfig/login thing? ==="
kubectl get ns platform-mesh-system 2>&1 | grep -av memcache | head -2
echo "=== is the LB/traefik still up (or did the whole gateway die)? ==="
kubectl -n default get pods 2>&1 | grep -av memcache | grep traefik
