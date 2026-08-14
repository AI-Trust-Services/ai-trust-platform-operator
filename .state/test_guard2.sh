#!/bin/bash
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
f(){ grep -avi memcache; }

# Use org=mirceatest (a real realm, currently owned by mttest3 in ns 1p2gonssnyvy9nhe, Ready).
# Create a duplicate for org=mirceatest in the provider ns → must Degrade (one-per-org), NOT stamp.
echo "=== existing owner of mirceatest: 1p2gonssnyvy9nhe/mttest3 (Ready). Create duplicate in $NS ==="
cat <<EOF | kubectl apply -f - 2>&1 | f
apiVersion: sub.aitrustmt.msp/v1alpha1
kind: Subscription
metadata: { name: dup-mirceatest, namespace: $NS }
spec: { displayName: "dup mirceatest", org: mirceatest, adminEmail: mircea.craciun@sap.com }
EOF
sleep 12
echo "=== duplicate phase + msg (expect Degraded, one-per-org, names the owner) ==="
kubectl -n "$NS" get subscriptions.sub.aitrustmt.msp dup-mirceatest -o jsonpath='phase={.status.phase}{"\n"}msg={.status.conditions[0].message}{"\n"}' 2>&1 | f
echo "=== original mttest3 still Ready? ==="
kubectl -n 1p2gonssnyvy9nhe get subscriptions.sub.aitrustmt.msp mttest3 -o jsonpath='phase={.status.phase} ready={.status.ready}{"\n"}' 2>&1 | f
echo "=== operator log: did it log the duplicate refusal? ==="
kubectl -n "$NS" logs deploy/aitrust-mt-operator --tail=40 2>&1 | f | grep -iE 'duplicate org|already owns|mirceatest' | tail -5
echo "=== cleanup ==="
kubectl -n "$NS" delete subscriptions.sub.aitrustmt.msp dup-mirceatest --ignore-not-found 2>&1 | f
echo DONE
