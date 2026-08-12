#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
echo "step1: mint shoot kubeconfig"
rm -f "$SHOOT_KUBECONFIG"
mint_shoot_kubeconfig >/dev/null 2>&1 && echo "  minted OK" || { echo "  MINT FAILED — garden login expired, run prerequisites/login.sh"; exit 3; }
echo "step2: kcp port-forward"
setup_kcp; kcp_portforward
for i in $(seq 1 20); do kc root get workspace >/dev/null 2>&1 && { echo "  kcp reachable"; break; }; sleep 2; done
trap 'pkill -f "port-forward.*root-proxy.*6443" 2>/dev/null || true' EXIT
WS=root:orgs:mirceatest3:accounttest
echo "step3: current bindings"
kc "$WS" get apibinding 2>&1 | grep -av memcache | grep -iE 'NAME|trust'
echo "step4: drop stale old-group binding(s)"
for b in $(kc "$WS" get apibinding -o json 2>/dev/null | python3 -c "import json,sys; [print(i['metadata']['name']) for i in json.load(sys.stdin).get('items',[]) if i.get('spec',{}).get('reference',{}).get('export',{}).get('name')=='trust.ai-trust.msp']" 2>/dev/null); do
  echo "  deleting $b"; kc "$WS" delete apibinding "$b" 2>&1 | grep -av memcache
done
echo "step5: bind new group"
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
echo "step6: wait Bound (max 60s)"
for i in $(seq 1 12); do
  P=$(kc "$WS" get apibinding aitrust-binding -o jsonpath='{.status.phase}' 2>/dev/null)
  echo "  phase=$P"; [ "$P" = "Bound" ] && break; sleep 5
done
kc "$WS" api-resources --api-group="$EXPORT_NAME" 2>&1 | grep -av memcache | grep -i aitrustplatforminstances && echo "DONE: mirceatest3:accounttest now on trust.aitrust.msp"
