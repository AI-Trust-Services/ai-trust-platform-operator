#!/bin/bash
exec > /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP/.state/src-d.out 2>&1
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
[ -s "$SHOOT_KUBECONFIG" ] || mint_shoot_kubeconfig || { echo LOGIN_EXPIRED; exit 3; }

echo "=== ALL CRDs matching aitrust (there may be TWO groups: trust.aitrust.msp AND trust.ai-trust.msp) ==="
kubectl get crd 2>&1 | grep -av memcache | grep -iE 'aitrust|ai-trust'
echo
echo "=== shoot-side: list instances for BOTH groups, all namespaces ==="
for G in aitrustplatforminstances.trust.aitrust.msp aitrustplatforminstances.trust.ai-trust.msp; do
  echo "-- $G --"
  kubectl get "$G" -A 2>&1 | grep -av memcache | head
done
echo
echo "=== operator logs: what is it reconciling / creating for 33hins0iklcwfg45-d ? ==="
kubectl -n "${PROVIDER_NS:-aitrust-msp}" logs deploy/aitrust-msp-operator --tail=60 2>&1 | grep -av memcache | grep -iE '33hins|reconcil|create|ns|route' | tail -25
echo DONE
