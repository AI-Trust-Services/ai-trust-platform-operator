#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config >/dev/null 2>&1
[ -s "$SHOOT_KUBECONFIG" ] || mint_shoot_kubeconfig
setup_kcp; kcp_portforward
trap 'pkill -f "port-forward.*root-proxy.*6443" 2>/dev/null || true' EXIT
echo "=== stores at ORG workspace root:orgs:aitrustmt (is there a per-account store here too?) ==="
kc root:orgs:aitrustmt get stores 2>&1 | grep -avi memcache | head
echo
echo "=== accounts under the org ==="
kc root:orgs:aitrustmt get accounts 2>&1 | grep -avi memcache | head
echo
echo "=== stores at child account root:orgs:aitrustmt:tenant ==="
kc root:orgs:aitrustmt:tenant get stores 2>&1 | grep -avi memcache | head
echo
echo "=== does the ORG store coreModule change once an app APIExport is bound? check aitrustdemo (older, app bound) types ==="
kc root:orgs get store aitrustdemo -o jsonpath='{.spec.coreModule}' 2>&1 | grep -avi memcache | grep -iE '^type |aitrust|intake|system' | head -30
echo
echo "=== APIBindings in the org workspace (what app APIs are bound) ==="
kc root:orgs:aitrustmt get apibindings 2>&1 | grep -avi memcache | head
echo "--- in child tenant ws ---"
kc root:orgs:aitrustmt:tenant get apibindings 2>&1 | grep -avi memcache | head
