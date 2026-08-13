#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config >/dev/null 2>&1
[ -s "$SHOOT_KUBECONFIG" ] || mint_shoot_kubeconfig
setup_kcp; kcp_portforward
trap 'pkill -f "port-forward.*root-proxy.*6443" 2>/dev/null || true' EXIT
echo "=== list ALL workspaceauthconfigs at root:orgs (per-org issuer CRs?) ==="
kc root:orgs get workspaceauthenticationconfigurations 2>&1 | grep -avi memcache | head -20
echo "--- issuers for each ---"
kc root:orgs get workspaceauthenticationconfigurations -o json 2>&1 | grep -avi memcache | python3 -c "
import sys,json
d=json.load(sys.stdin)
for it in d.get('items',[]):
  n=it['metadata']['name']
  for e in it['spec'].get('jwt',[]):
    print(n,'->',e['issuer']['url'])
" 2>&1 | head -30
echo
echo "=== confirm aitrustmt org has its own auth config w/ realm issuer ==="
kc root:orgs get workspaceauthenticationconfiguration aitrustmt -o json 2>&1 | grep -avi memcache | python3 -c "import sys,json; d=json.load(sys.stdin); [print(e['issuer']['url'],'aud=',e['issuer'].get('audiences'),'user=',e.get('claimMappings',{}).get('username')) for e in d['spec']['jwt']]" 2>&1 | head
