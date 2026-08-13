#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config >/dev/null 2>&1
[ -s "$SHOOT_KUBECONFIG" ] || mint_shoot_kubeconfig
setup_kcp; kcp_portforward
trap 'pkill -f "port-forward.*root-proxy.*6443" 2>/dev/null || true' EXIT
for WS in root root:orgs root:orgs:aitrustmt root:orgs:aitrustmt:tenant; do
  echo "=== WorkspaceAuthenticationConfiguration @ $WS ==="
  kc "$WS" get workspaceauthenticationconfigurations -o yaml 2>&1 | grep -avi memcache | grep -iE 'name:|issuer|jwksUri|audience|claim|username|prefix' | head -20
  echo
done
echo "=== the invite CR aitrustmt (full) ==="
kc root:orgs:aitrustmt get invite aitrustmt -o yaml 2>&1 | grep -avi memcache | grep -vE 'managedFields|f:|manager:|operation:|time:|apiVersion: apis' | head -40
