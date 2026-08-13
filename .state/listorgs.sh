#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config
KCFG="$BUNDLE/.state/kcp-admin.kubeconfig"
[ -s "$KCFG" ] || { echo "no kcp-admin kubeconfig at $KCFG"; exit 1; }
export KUBECONFIG="$KCFG"
echo "=== kcp current context ==="
kubectl config current-context 2>&1 | grep -avi memcache
echo "=== org accounts (root:orgs) ==="
kubectl get accounts.core.platform-mesh.io -A 2>&1 | grep -avi memcache | head -30 || \
  kubectl get accounts -A 2>&1 | grep -avi memcache | head -30
echo "=== WorkspaceAuthenticationConfigurations (name == org, issuer names the realm) ==="
kubectl get workspaceauthenticationconfigurations.tenancy.kcp.io -A 2>&1 | grep -avi memcache | head -30
echo DONE
