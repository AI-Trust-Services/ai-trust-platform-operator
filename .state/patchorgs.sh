#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
patch_one(){ ns=$1; nm=$2; org=$3
  echo "=== patch $ns/$nm spec.org=$org ==="
  kubectl -n "$ns" patch subscriptions.sub.aitrustmt.msp "$nm" --type=merge -p "{\"spec\":{\"org\":\"$org\"}}" 2>&1 | grep -avi memcache
  sleep 3
  echo "  spec.org now: $(kubectl -n "$ns" get subscriptions.sub.aitrustmt.msp "$nm" -o jsonpath='{.spec.org}' 2>&1 | grep -avi memcache)"
}
patch_one bayq7srx101gga1s mttest2 mttest
patch_one 38ef9l9wvvoacrsm pocmt poc2
patch_one 33r3aesqz4gz9z4a my-subscription aitrustmt
echo "=== wait for reconcile, then check if spec.org STUCK (syncagent may revert) + status ==="
sleep 15
for row in bayq7srx101gga1s/mttest2 38ef9l9wvvoacrsm/pocmt 33r3aesqz4gz9z4a/my-subscription; do
  ns=${row%/*}; nm=${row#*/}
  echo "[$row] org=$(kubectl -n "$ns" get subscriptions.sub.aitrustmt.msp "$nm" -o jsonpath='{.spec.org}' 2>&1 | grep -avi memcache) phase=$(kubectl -n "$ns" get subscriptions.sub.aitrustmt.msp "$nm" -o jsonpath='{.status.phase}' 2>&1 | grep -avi memcache) url=$(kubectl -n "$ns" get subscriptions.sub.aitrustmt.msp "$nm" -o jsonpath='{.status.url}' 2>&1 | grep -avi memcache)"
done
echo DONE
