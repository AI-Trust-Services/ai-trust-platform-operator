#!/bin/bash
exec > /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP/.state/verify-d.out 2>&1
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
[ -s "$SHOOT_KUBECONFIG" ] || mint_shoot_kubeconfig || { echo LOGIN_EXPIRED; exit 3; }
GWNS=platform-mesh-system

echo "=== namespaces now (both d should be gone or Terminating; testai + my-aitrust Active) ==="
kubectl get ns 2>&1 | grep -av memcache | grep -E 'aitp-|NAME'
echo
echo "=== d-related HTTPRoutes — re-check TWICE 20s apart to see if operator is RE-CREATING them ==="
kubectl -n "$GWNS" get httproute 2>&1 | grep -av memcache | grep -E '\-d\-(app|keycloak)' | awk '{print $1, $NF}' || echo "  (none)"
echo "--- wait 20s ---"; sleep 20
kubectl -n "$GWNS" get httproute 2>&1 | grep -av memcache | grep -E '\-d\-(app|keycloak)' | awk '{print $1, $NF}' || echo "  (none)"
echo
echo "=== any shoot-mirrored CR still named d? (the syncagent mirror the operator reconciles) ==="
kubectl get aitrustplatforminstance -A 2>&1 | grep -av memcache | grep -E 'NAME|(^| )d( |$)' || echo "  (no d mirror)"
echo DONE
