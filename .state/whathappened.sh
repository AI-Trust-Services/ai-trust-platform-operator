#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
echo "=== A) are the mesh + provider still alive, or is the WHOLE shoot wiped? ==="
kubectl get ns 2>&1 | grep -avi memcache | grep -E 'platform-mesh-system|aitrust-msp|default|NAME' | head
echo "=== B) is the MSP provider (operator/syncagent) still running? ==="
kubectl -n aitrust-msp get deploy 2>&1 | grep -avi memcache | head
echo "=== C) do the CONSUMER CRs (AITrustPlatformInstance) still exist? (source of truth) ==="
setup_kcp >/dev/null 2>&1; kcp_portforward >/dev/null 2>&1
for i in $(seq 1 15); do kc root get workspace >/dev/null 2>&1 && break; sleep 2; done
for WS in root:orgs:aitrustg2:demo root:orgs:mirceatest3:accounttest; do
  echo "-- $WS --"; kc "$WS" -n default get aitrustplatforminstance 2>&1 | grep -avi memcache | head
done
echo "=== D) shoot-side mirrored CRs (what the operator reconciles) ==="
kubectl get aitrustplatforminstance -A 2>&1 | grep -avi memcache | head
echo "=== E) operator alive + recent logs (did it DELETE everything, or did something else?) ==="
kubectl -n aitrust-msp get pods 2>&1 | grep -avi memcache | grep -E 'operator|syncagent'
kubectl -n aitrust-msp logs deploy/aitrust-msp-operator --tail=30 2>&1 | grep -avi memcache | grep -iE 'delet|finaliz|error|reconcil' | tail -15
