#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config >/dev/null 2>&1
[ -s "$SHOOT_KUBECONFIG" ] || mint_shoot_kubeconfig
setup_kcp; kcp_portforward
trap 'pkill -f "port-forward.*root-proxy.*6443" 2>/dev/null || true' EXIT
echo "KCP_HOST=$KCP_HOST"
echo "=== Store CRD group (from root:orgs) ==="
kc root:orgs api-resources 2>&1 | grep -avi memcache | grep -iE 'store|account|fga' | head
echo
echo "=== Stores in root:orgs (one per org?) ==="
kc root:orgs get stores 2>&1 | grep -avi memcache | head -30
echo
echo "=== the aitrustmt Store CR (full yaml) ==="
kc root:orgs get store aitrustmt -o yaml 2>&1 | grep -avi memcache | head -80
echo
echo "=== Accounts in root:orgs ==="
kc root:orgs get accounts 2>&1 | grep -avi memcache | head -20
