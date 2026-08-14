#!/bin/bash
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
f(){ grep -avi memcache; }
echo "=== ALL subscriptions cluster-wide (ns / name / org / phase) ==="
kubectl get subscriptions.sub.aitrustmt.msp -A -o jsonpath='{range .items[*]}{.metadata.namespace}  {.metadata.name}  org={.spec.org}  phase={.status.phase}{"\n"}{end}' 2>&1 | f
echo
echo "=== is fridaytest owned by anyone now? count active fridaytest subs ==="
kubectl get subscriptions.sub.aitrustmt.msp -A -o jsonpath='{range .items[?(@.spec.org=="fridaytest")]}{.metadata.namespace}/{.metadata.name} phase={.status.phase}{"\n"}{end}' 2>&1 | f
echo DONE
