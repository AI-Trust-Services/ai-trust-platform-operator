#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config >/dev/null 2>&1
[ -s "$SHOOT_KUBECONFIG" ] || mint_shoot_kubeconfig
setup_kcp; kcp_portforward
trap 'pkill -f "port-forward.*root-proxy.*6443" 2>/dev/null || true' EXIT
echo "=== WorkspaceAuthenticationConfiguration CR names @ root ==="
kc root get workspaceauthenticationconfigurations 2>&1 | grep -avi memcache | head
echo
echo "=== how many jwt issuers in orgs-authentication (one CR, many jwt entries?) ==="
kc root get workspaceauthenticationconfiguration orgs-authentication -o json 2>&1 | grep -avi memcache | python3 -c "import sys,json; d=json.load(sys.stdin); j=d['spec']['jwt']; print('jwt entries:',len(j)); [print(' -', e['issuer']['url'],'aud=',e['issuer'].get('audiences')) for e in j]" 2>&1 | head -30
echo
echo "=== invite aitrustmt spec/status ==="
kc root:orgs:aitrustmt get invite aitrustmt -o json 2>&1 | grep -avi memcache | python3 -c "import sys,json; d=json.load(sys.stdin); print('SPEC:',json.dumps(d.get('spec',{}),indent=1)); print('STATUS:',json.dumps(d.get('status',{}),indent=1)[:800])" 2>&1 | head -40
