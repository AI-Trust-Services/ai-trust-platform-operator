#!/bin/bash
exec > /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP/.state/oidc-detail.out 2>&1
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
[ -s "$SHOOT_KUBECONFIG" ] || mint_shoot_kubeconfig || { echo LOGIN_EXPIRED; exit 3; }
GWNS=platform-mesh-system

echo "############ 1. FrontProxy CR full spec (auth block, additionalHostnames, cert issuerRef) ############"
kubectl -n "$GWNS" get frontproxies.operator.kcp.io frontproxy -o yaml 2>&1 | grep -avi memcache | sed -n '1,140p'

echo
echo "############ 2. RootShard CR full spec (the auth/oidc feature-gate context + cert SANs) ############"
kubectl -n "$GWNS" get rootshards.operator.kcp.io root -o yaml 2>&1 | grep -avi memcache | sed -n '1,160p'
echo DONE
