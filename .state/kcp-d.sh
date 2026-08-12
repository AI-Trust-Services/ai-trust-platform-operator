#!/bin/bash
exec > /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP/.state/kcp-d.out 2>&1
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
[ -s "$SHOOT_KUBECONFIG" ] || mint_shoot_kubeconfig || { echo LOGIN_EXPIRED; exit 3; }
setup_kcp >/dev/null 2>&1; kcp_portforward >/dev/null 2>&1
for i in $(seq 1 15); do kc root get workspace >/dev/null 2>&1 && break; sleep 2; done
CID=33hins0iklcwfg45   # == the consumer workspace cluster-id (namespace prefix)

echo "=== address the consumer ws by cluster-id: /clusters/$CID — list AITrustPlatformInstance ==="
kc "$CID" get aitrustplatforminstance -A 2>&1 | grep -av memcache | head
echo
echo "=== delete ONLY d in that workspace (the authoritative upstream object) ==="
NS=$(kc "$CID" get aitrustplatforminstance -A --no-headers 2>/dev/null | grep -av memcache | awk '$2=="d"{print $1}' | head -1)
echo "  d lives in kcp ns: '$NS'"
if [ -n "$NS" ]; then
  kc "$CID" -n "$NS" delete aitrustplatforminstance d 2>&1 | grep -av memcache
else
  echo "  (could not resolve d's namespace in this ws — not deleting)"
fi
echo
echo "=== wait, then confirm d gone upstream + downstream, testai intact ==="
sleep 25
echo "-- upstream CRs in $CID --"
kc "$CID" get aitrustplatforminstance -A 2>&1 | grep -av memcache | head
echo "-- shoot mirror --"
kubectl -n "$CID" get aitrustplatforminstances.trust.aitrust.msp 2>&1 | grep -av memcache
echo "-- namespaces --"
kubectl get ns 2>&1 | grep -av memcache | grep -E 'aitp-|NAME'
echo DONE
