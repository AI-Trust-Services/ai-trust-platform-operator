#!/bin/bash
exec > /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP/.state/kcp-d2.out 2>&1
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
[ -s "$SHOOT_KUBECONFIG" ] || mint_shoot_kubeconfig || { echo LOGIN_EXPIRED; exit 3; }
setup_kcp >/dev/null 2>&1; kcp_portforward >/dev/null 2>&1
for i in $(seq 1 15); do kc root get workspace >/dev/null 2>&1 && break; sleep 2; done
CID=33hins0iklcwfg45

echo "=== query the EXACT coords from the mirror: cluster $CID, namespace default ==="
kc "$CID" -n default get aitrustplatforminstance 2>&1 | grep -av memcache
echo "--- also try the CRD-group plural explicitly ---"
kc "$CID" -n default get aitrustplatforminstances.trust.aitrust.msp 2>&1 | grep -av memcache

echo "=== delete d in cluster $CID namespace default (authoritative upstream) ==="
kc "$CID" -n default delete aitrustplatforminstance d 2>&1 | grep -av memcache

echo "=== wait, confirm gone upstream + mirror stops recreating ==="
sleep 30
echo "-- upstream (cluster $CID / default) --"
kc "$CID" -n default get aitrustplatforminstance 2>&1 | grep -av memcache
echo "-- shoot mirror (recreated? or gone?) --"
kubectl -n "$CID" get aitrustplatforminstances.trust.aitrust.msp 2>&1 | grep -av memcache
echo "-- namespaces --"
kubectl get ns 2>&1 | grep -av memcache | grep -E 'aitp-|NAME'
echo "-- testai intact? --"
kubectl -n "$CID" get aitrustplatforminstances.trust.aitrust.msp testai -o jsonpath='testai ready={.status.ready} phase={.status.phase}{"\n"}' 2>&1 | grep -av memcache
echo DONE
