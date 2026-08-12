#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
setup_kcp >/dev/null 2>&1; kcp_portforward >/dev/null 2>&1
trap 'pkill -f "port-forward.*root-proxy.*6443" 2>/dev/null || true' EXIT
# cleanup probe
kc root:orgs:mirceatest3:accounttest -n default delete aitrustplatforminstance probe-create >/dev/null 2>&1
echo "=== working private-llm create-view node (FULL) via the AiTrust bundle shoot kubeconfig ==="
sk -n platform-mesh-system run pw-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet -- \
  curl -sS http://private-llm-portal-integration.private-llm.svc.cluster.local/pm-content.json 2>/dev/null > "$STATE/pll-content.json"
wc -c "$STATE/pll-content.json"
python3 -c "
import json
d=json.load(open('$STATE/pll-content.json'))
n=d['luigiConfigFragment']['data']['nodes'][0]
rd=n['context']['resourceDefinition']
print('node keys:', list(n.keys()))
print('rd keys:', list(rd.keys()))
print('group=',rd.get('group'),'version=',rd.get('version'),'plural=',rd.get('plural'),'kind=',rd.get('kind'),'scope=',rd.get('scope'))
print('has ui.createView?', 'createView' in rd.get('ui',{}))
import json as j; print('createView=', j.dumps(rd.get('ui',{}).get('createView'))[:400])
"
