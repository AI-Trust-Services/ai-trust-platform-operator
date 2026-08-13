#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
echo "=== ALL subscriptions final status ==="
for row in $(kubectl get subscriptions.sub.aitrustmt.msp -A -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name}{"\n"}{end}' 2>/dev/null | grep -avi memcache); do
  ns=${row%/*}; nm=${row#*/}
  echo "[$nm] org=$(kubectl -n "$ns" get subscriptions.sub.aitrustmt.msp "$nm" -o jsonpath='{.spec.org}' 2>&1|grep -avi memcache) phase=$(kubectl -n "$ns" get subscriptions.sub.aitrustmt.msp "$nm" -o jsonpath='{.status.phase}' 2>&1|grep -avi memcache) url=$(kubectl -n "$ns" get subscriptions.sub.aitrustmt.msp "$nm" -o jsonpath='{.status.url}' 2>&1|grep -avi memcache)"
done
echo "=== per-org oauth2-proxies running ==="
kubectl -n "$NS" get deploy -l app=oauth2-proxy-org --no-headers 2>&1 | grep -avi memcache | awk '{print "  "$1" "$2}'
echo DONE
