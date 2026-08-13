#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config
[ -s "$SHOOT_KUBECONFIG" ] && kubectl --kubeconfig "$SHOOT_KUBECONFIG" get ns >/dev/null 2>&1 || { rm -f "$SHOOT_KUBECONFIG"; mint_shoot_kubeconfig >/dev/null 2>&1 || { echo LOGIN_EXPIRED; exit 3; }; }
export KUBECONFIG="$SHOOT_KUBECONFIG"
echo "=== Subscription CRs (all) — status ==="
kubectl get subscriptions.sub.aitrustmt.msp -A -o custom-columns='NS:.metadata.namespace,NAME:.metadata.name,READY:.status.ready,PHASE:.status.phase,REALM:.status.realm,URL:.status.url' 2>&1 | grep -avi memcache
echo "=== the pocmt subscription (host prefix 38ef9l9wvvoacrsm = its account cluster-id) ==="
kubectl get subscriptions.sub.aitrustmt.msp -A 2>&1 | grep -avi memcache | grep -iE 'pocmt|38ef9'
echo "=== operator running + recent logs on pocmt ==="
kubectl -n aitrust-mt-msp get deploy aitrust-mt-operator 2>&1 | grep -avi memcache
kubectl -n aitrust-mt-msp logs deploy/aitrust-mt-operator --tail=40 2>&1 | grep -avi memcache | grep -iE 'pocmt|38ef9|error|reconcil|provision|realm|job' | tail -20
echo "=== provision job(s) + pods for pocmt ==="
kubectl -n aitrust-mt-msp get jobs 2>&1 | grep -avi memcache | grep -iE 'pocmt|38ef9|prov|NAME'
kubectl -n aitrust-mt-msp get pods 2>&1 | grep -avi memcache | grep -iE 'prov|38ef9|pocmt'
echo DONE
