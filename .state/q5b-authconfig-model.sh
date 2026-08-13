#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config >/dev/null 2>&1
[ -s "$SHOOT_KUBECONFIG" ] || mint_shoot_kubeconfig
setup_kcp; kcp_portforward
trap 'pkill -f "port-forward.*root-proxy.*6443" 2>/dev/null || true' EXIT
echo "=== WorkspaceAuthenticationConfiguration in org ws (realm/issuer binding) ==="
kc root:orgs:aitrustmt get workspaceauthenticationconfigurations 2>&1 | grep -avi memcache | head
echo "--- full yaml (issuer URL -> realm) ---"
kc root:orgs:aitrustmt get workspaceauthenticationconfigurations -o yaml 2>&1 | grep -avi memcache | grep -iE 'name:|issuer|jwks|audience|username|claim|realm|url' | head -30
echo
echo "=== authorizationmodels resource in org ws (app model-extension seam?) ==="
kc root:orgs:aitrustmt get authorizationmodels 2>&1 | grep -avi memcache | head
echo "--- any authorizationmodels at root:orgs ---"
kc root:orgs get authorizationmodels 2>&1 | grep -avi memcache | head
echo "--- full yaml of one if present ---"
kc root:orgs:aitrustmt get authorizationmodels -o yaml 2>&1 | grep -avi memcache | head -40
echo
echo "=== invites resource (user onboarding into realm+store) ==="
kc root:orgs:aitrustmt get invites 2>&1 | grep -avi memcache | head
