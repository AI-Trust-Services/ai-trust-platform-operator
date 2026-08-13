#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
echo "=== all Subscriptions on the shoot (all ns) ==="
kubectl get subscriptions.sub.aitrustmt.msp -A 2>&1 | grep -avi memcache
echo "=== full spec + status + annotations of each ==="
for row in $(kubectl get subscriptions.sub.aitrustmt.msp -A -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name}{"\n"}{end}' 2>/dev/null | grep -avi memcache); do
  ns=${row%/*}; nm=${row#*/}
  echo "---- [$row] ----"
  echo "spec:"; kubectl -n "$ns" get subscriptions.sub.aitrustmt.msp "$nm" -o jsonpath='{.spec}{"\n"}' 2>&1 | grep -avi memcache
  echo "status.phase/url/realm:"; kubectl -n "$ns" get subscriptions.sub.aitrustmt.msp "$nm" -o jsonpath='  {.status.phase} | {.status.url} | realm={.status.realm} | {.status.conditions[0].message}{"\n"}' 2>&1 | grep -avi memcache
  echo "annotations:"; kubectl -n "$ns" get subscriptions.sub.aitrustmt.msp "$nm" -o jsonpath='{.metadata.annotations}{"\n"}' 2>&1 | grep -avi memcache | tr ',' '\n' | grep -iE 'kcp|remote-object|path' | head
done
echo DONE
