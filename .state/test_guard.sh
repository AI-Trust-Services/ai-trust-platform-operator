#!/bin/bash
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
f(){ grep -avi memcache; }

# The original fridaytest sub lives in ns 1nqv0yinuy04ph1b (name r). Create a DUPLICATE in the provider ns
# for org=fridaytest and watch the guard reject it.
echo "=== create duplicate subscription (org=fridaytest) in ns $NS ==="
cat <<EOF | kubectl apply -f - 2>&1 | f
apiVersion: sub.aitrustmt.msp/v1alpha1
kind: Subscription
metadata:
  name: dup-fridaytest-test
  namespace: $NS
spec:
  displayName: "duplicate test"
  org: fridaytest
  adminEmail: mircea.craciun@sap.com
EOF

echo "=== wait ~10s for reconcile ==="
sleep 12
echo "=== the duplicate's phase + message (expect Degraded, one-per-org) ==="
kubectl -n "$NS" get subscriptions.sub.aitrustmt.msp dup-fridaytest-test -o jsonpath='phase={.status.phase}{"\n"}msg={.status.conditions[0].message}{"\n"}' 2>&1 | f

echo "=== original fridaytest sub still Ready? ==="
kubectl -n 1nqv0yinuy04ph1b get subscriptions.sub.aitrustmt.msp r -o jsonpath='phase={.status.phase} ready={.status.ready}{"\n"}' 2>&1 | f

echo "=== NO second oauth2-proxy/host stamped for the dup (only the one owner proxy) ==="
kubectl -n "$NS" get deploy -l org=fridaytest --no-headers 2>&1 | f

echo "=== cleanup: delete the duplicate test sub ==="
kubectl -n "$NS" delete subscriptions.sub.aitrustmt.msp dup-fridaytest-test --ignore-not-found 2>&1 | f
echo DONE
