#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
exec > .state/inv3-kcp-auth.out 2>&1
K(){ kubectl "$@" 2>&1 | grep -avi memcache; }

setup_kcp
kcp_portforward
echo "KCP_HOST=$KCP_HOST"
echo

echo "############ API resources containing 'authentication' at root ############"
kc root api-resources 2>&1 | grep -aiE 'auth|oidc' | grep -avi memcache

echo; echo "############ orgs workspaces ############"
kc root:orgs get workspaces 2>&1 | grep -avi memcache

echo; echo "############ Look for WorkspaceAuthenticationConfiguration-like types ############"
kc root api-resources 2>&1 | grep -avi memcache | grep -aiE 'workspace|tenancy|core.kcp'
