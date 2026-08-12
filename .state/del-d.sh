#!/bin/bash
exec > /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP/.state/del-d.out 2>&1
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
[ -s "$SHOOT_KUBECONFIG" ] || mint_shoot_kubeconfig || { echo LOGIN_EXPIRED; exit 3; }
GWNS=platform-mesh-system

echo "=== [1] delete the CR 'd' in root:orgs:aitrustg2:demo (finalizer tears down aitp-25veqwflh7syq7fm-d) ==="
setup_kcp >/dev/null 2>&1; kcp_portforward >/dev/null 2>&1
for i in $(seq 1 15); do kc root get workspace >/dev/null 2>&1 && break; sleep 2; done
kc root:orgs:aitrustg2:demo -n default delete aitrustplatforminstance d --wait=false 2>&1 | grep -av memcache

echo "=== [2] orphan namespace aitp-33hins0iklcwfg45-d (no CR) — its HTTPRoutes in $GWNS ==="
kubectl -n "$GWNS" get httproute 2>&1 | grep -av memcache | grep -E 'NAME|33hins0iklcwfg45-d' || echo "  (none)"
echo "--- deleting orphan routes + namespace ---"
kubectl -n "$GWNS" delete httproute aitp-33hins0iklcwfg45-d-app aitp-33hins0iklcwfg45-d-keycloak --ignore-not-found 2>&1 | grep -av memcache
kubectl delete ns aitp-33hins0iklcwfg45-d --wait=false 2>&1 | grep -av memcache

echo
echo "=== give the finalizer a moment, then show remaining aitp-* namespaces ==="
sleep 15
kubectl get ns 2>&1 | grep -av memcache | grep -E 'aitp-|NAME'
echo "=== remaining d-related HTTPRoutes (expect only 25veqw... briefly, then gone) ==="
kubectl -n "$GWNS" get httproute 2>&1 | grep -av memcache | grep -E '\-d\-(app|keycloak)' || echo "  (none)"
echo DONE
