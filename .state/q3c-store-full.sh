#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config >/dev/null 2>&1
[ -s "$SHOOT_KUBECONFIG" ] || mint_shoot_kubeconfig
setup_kcp; kcp_portforward
trap 'pkill -f "port-forward.*root-proxy.*6443" 2>/dev/null || true' EXIT
echo "=== FULL Store spec.coreModule for aitrustmt ==="
kc root:orgs get store aitrustmt -o jsonpath='{.spec.coreModule}' 2>&1 | grep -avi memcache
echo
echo "=== Store status (OpenFGA store id / model id) ==="
kc root:orgs get store aitrustmt -o jsonpath='{.status}' 2>&1 | grep -avi memcache
echo
echo "=== does Store spec have other fields (additionalModules?) ==="
kc root:orgs get store aitrustmt -o json 2>&1 | grep -avi memcache | python3 -c "import sys,json; d=json.load(sys.stdin); print('SPEC KEYS:', list(d['spec'].keys())); print('STATUS KEYS:', list(d.get('status',{}).keys()))" 2>&1
