#!/bin/bash
exec > /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP/.state/kill-d.out 2>&1
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
[ -s "$SHOOT_KUBECONFIG" ] || mint_shoot_kubeconfig || { echo LOGIN_EXPIRED; exit 3; }
G=aitrustplatforminstances.trust.aitrust.msp
MNS=33hins0iklcwfg45
GWNS=platform-mesh-system

echo "=== BEFORE: the two CRs in $MNS (must delete ONLY d, KEEP testai) ==="
kubectl -n "$MNS" get "$G" 2>&1 | grep -av memcache

echo "=== delete ONLY the d CR (finalizer tears down aitp-33hins0iklcwfg45-d cleanly) ==="
kubectl -n "$MNS" delete "$G" d --wait=false 2>&1 | grep -av memcache

echo "=== the namespace is stuck Terminating because the operator kept recreating content; once the CR is"
echo "    gone the requeue stops. Nudge the stray routes out too. ==="
kubectl -n "$GWNS" delete httproute aitp-33hins0iklcwfg45-d-app aitp-33hins0iklcwfg45-d-keycloak --ignore-not-found 2>&1 | grep -av memcache

echo "=== wait for teardown, verify d gone / testai intact ==="
sleep 25
echo "-- CRs in $MNS now --"
kubectl -n "$MNS" get "$G" 2>&1 | grep -av memcache
echo "-- namespaces --"
kubectl get ns 2>&1 | grep -av memcache | grep -E 'aitp-|NAME'
echo "-- d routes (expect none) --"
kubectl -n "$GWNS" get httproute 2>&1 | grep -av memcache | grep -E '\-d\-(app|keycloak)' || echo "  (none)"
echo "-- testai still Ready? --"
kubectl -n "$MNS" get "$G" testai -o jsonpath='testai phase={.status.phase} ready={.status.ready}{"\n"}' 2>&1 | grep -av memcache
echo DONE
