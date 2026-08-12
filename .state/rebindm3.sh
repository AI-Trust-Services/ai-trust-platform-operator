#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
setup_kcp; kcp_portforward
for i in $(seq 1 15); do kc root get workspace >/dev/null 2>&1 && break; sleep 2; done
trap 'pkill -f "port-forward.*root-proxy.*6443" 2>/dev/null || true' EXIT
WS=root:orgs:mirceatest3:accounttest
echo "=== current bindings in $WS (find the stale old-group one) ==="
kc "$WS" get apibinding 2>&1 | grep -av memcache | grep -iE 'NAME|trust'
echo "=== delete any binding to the OLD group trust.ai-trust.msp ==="
for b in $(kc "$WS" get apibinding -o json 2>/dev/null | python3 -c "import json,sys; [print(i['metadata']['name']) for i in json.load(sys.stdin).get('items',[]) if i.get('spec',{}).get('reference',{}).get('export',{}).get('name')=='trust.ai-trust.msp']" 2>/dev/null); do
  echo "deleting stale binding $b"; kc "$WS" delete apibinding "$b" 2>&1 | grep -av memcache
done
echo "=== bind the NEW group trust.aitrust.msp ==="
kc "$WS" apply -f - <<EOF 2>&1 | grep -av memcache
apiVersion: apis.kcp.io/v1alpha2
kind: APIBinding
metadata: { name: aitrust-binding }
spec:
  reference: { export: { path: ${PROVIDER_WS}, name: ${EXPORT_NAME} } }
  permissionClaims:
  - {group: "", resource: secrets, verbs: ["*"], selector: {matchAll: true}, state: Accepted}
  - {group: "", resource: namespaces, verbs: ["*"], selector: {matchAll: true}, state: Accepted}
  - {group: "", resource: events, verbs: ["*"], selector: {matchAll: true}, state: Accepted}
EOF
bnd(){ kc "$WS" get apibinding aitrust-binding -o jsonpath='{.status.phase}' 2>/dev/null | grep -qx Bound; }
wait_for 180 5 "aitrust-binding Bound in mirceatest3:accounttest" bnd
kc "$WS" api-resources --api-group="$EXPORT_NAME" 2>&1 | grep -av memcache | grep -i aitrustplatforminstances
ok "mirceatest3:accounttest re-bound to trust.aitrust.msp — create form will work there now"
