#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
line(){ echo "== $1 =="; }
line "existing pocmt Subscription: what realm/url/tenantId did the operator set?"
# find the subscription CR (mirrored ns) on the shoot
kubectl get subscriptions.sub.aitrustmt.msp -A 2>/dev/null | grep -avi memcache
echo "--- status of each ---"
for row in $(kubectl get subscriptions.sub.aitrustmt.msp -A -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name}{"\n"}{end}' 2>/dev/null | grep -avi memcache); do
  ns=${row%/*}; nm=${row#*/}
  echo "[$row]"
  kubectl -n "$ns" get subscriptions.sub.aitrustmt.msp "$nm" -o jsonpath='  realm={.status.realm} tenantId={.status.tenantId} phase={.status.phase} url={.status.url}{"\n"}' 2>/dev/null | grep -avi memcache
  echo "  annotations:"; kubectl -n "$ns" get subscriptions.sub.aitrustmt.msp "$nm" -o jsonpath='{range .metadata.annotations}{@}{end}' 2>/dev/null | grep -avi memcache | tr ',' '\n' | grep -iE 'kcp.io/path|remote-object' | head
done
echo DONE
