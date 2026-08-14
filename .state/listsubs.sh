#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
echo "=== all sub.aitrustmt.msp Subscriptions (ns/name, org, phase, url) ==="
kubectl get subscriptions.sub.aitrustmt.msp -A -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name}  org={.spec.org}  phase={.status.phase}  url={.status.url}{"\n"}{end}' 2>&1 | grep -avi memcache
echo DONE
