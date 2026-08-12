#!/bin/bash
exec > /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP/.state/final-d.out 2>&1
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
[ -s "$SHOOT_KUBECONFIG" ] || mint_shoot_kubeconfig || { echo LOGIN_EXPIRED; exit 3; }
GWNS=platform-mesh-system
sleep 20
echo "=== namespaces (d should be GONE now) ==="
kubectl get ns 2>&1 | grep -av memcache | grep -E 'aitp-|NAME'
echo "=== any d HTTPRoutes left? (expect none) ==="
kubectl -n "$GWNS" get httproute 2>&1 | grep -av memcache | grep -E '\-d\-(app|keycloak)' || echo "  (none — clean)"
echo "=== remaining live instances (mirror) ==="
kubectl get aitrustplatforminstances.trust.aitrust.msp -A 2>&1 | grep -av memcache
kubectl get aitrustplatforminstances.trust.ai-trust.msp -A 2>&1 | grep -av memcache
echo "=== operator: still erroring on d? (expect NO more 'd' terminating errors) ==="
kubectl -n "${PROVIDER_NS:-aitrust-msp}" logs deploy/aitrust-msp-operator --tail=15 2>&1 | grep -av memcache | grep -iE 'error|"d"' | tail -5 || echo "  (no recent d errors)"
echo DONE
