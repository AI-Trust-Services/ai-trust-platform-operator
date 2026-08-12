#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
setup_kcp; kcp_portforward
trap 'pkill -f "port-forward.*root-proxy.*6443" 2>/dev/null || true' EXIT
echo "=== CRD real names (source of the GraphQL type) ==="
sk get crd aitrustplatforminstances.trust.ai-trust.msp -o jsonpath='plural={.spec.names.plural} singular={.spec.names.singular} kind={.spec.names.kind} listKind={.spec.names.listKind}{"\n"}' 2>&1 | grep -av memcache
echo "=== user org mirceatest3 / account accounttest exist + APIBinding? ==="
kc root:orgs get workspace mirceatest3 2>&1 | grep -av memcache | head -2
kc root:orgs:mirceatest3 get workspace accounttest 2>&1 | grep -av memcache | head -2
echo "--- APIBinding in that account ---"
kc root:orgs:mirceatest3:accounttest get apibinding 2>&1 | grep -av memcache | grep -iE 'NAME|aitrust|trust.ai'
echo "--- is the CR API served there? ---"
kc root:orgs:mirceatest3:accounttest api-resources --api-group=trust.ai-trust.msp 2>&1 | grep -av memcache | head
echo "=== the APIResourceSchema the syncagent published (name embeds a hash) ==="
kc "$PROVIDER_WS" get apiresourceschema 2>&1 | grep -av memcache
echo "=== does that schema have version v1alpha1 + proper spec? ==="
SCH=$(kc "$PROVIDER_WS" get apiresourceschema -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
kc "$PROVIDER_WS" get apiresourceschema "$SCH" -o jsonpath='names={.spec.names} group={.spec.group} versions={range .spec.versions[*]}{.name}{" served="}{.served}{" "}{end}{"\n"}' 2>&1 | grep -av memcache | head -c 400; echo
