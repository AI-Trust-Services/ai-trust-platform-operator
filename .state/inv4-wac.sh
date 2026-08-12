#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
exec > .state/inv4-wac.out 2>&1
K(){ kubectl "$@" 2>&1 | grep -avi memcache; }

setup_kcp
kcp_portforward

for WS in root root:orgs root:orgs:aitrustdemo root:orgs:demo; do
  echo "############################################################"
  echo "### WorkspaceAuthenticationConfiguration in: $WS"
  echo "############################################################"
  kc "$WS" get workspaceauthenticationconfigurations 2>&1 | grep -avi memcache
  echo "--- full yaml ---"
  kc "$WS" get workspaceauthenticationconfigurations -o yaml 2>&1 | grep -avi 'managedFields' | grep -avi memcache
  echo
done
