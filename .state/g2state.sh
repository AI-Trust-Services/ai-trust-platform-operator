#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
setup_kcp; kcp_portforward
trap 'pkill -f "port-forward.*root-proxy.*6443" 2>/dev/null || true' EXIT
echo "=== org aitrustg2 / account demo state ==="
kc root:orgs get account aitrustg2 -o jsonpath='org ready={.status.conditions[?(@.type=="Ready")].status}{"\n"}' 2>&1 | grep -av memcache
kc root:orgs:aitrustg2 get account demo -o jsonpath='acct ready={.status.conditions[?(@.type=="Ready")].status}{"\n"}' 2>&1 | grep -av memcache
echo "=== binding in aitrustg2:demo ==="
kc root:orgs:aitrustg2:demo get apibinding 2>&1 | grep -av memcache | grep -iE 'NAME|aitrust'
echo "=== is the new-group API served there? ==="
kc root:orgs:aitrustg2:demo api-resources --api-group=trust.aitrust.msp 2>&1 | grep -av memcache | head
