#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
echo "=== gateway logs: schema generation for trust.ai-trust.msp (errors/skips) ==="
sk -n "$MESH_NS" logs deploy/kubernetes-graphql-gateway-listener --tail=300 2>&1 | grep -av memcache \
  | grep -iE 'trust.ai|aitrust|AITrustPlatform|undefined|skip|invalid|error.*schema|cannot' | tail -20
echo ""
echo "=== the FULL schema of my APIResourceSchema — check for gateway-hostile constructs ==="
SCH=v3e8f1826.aitrustplatforminstances.trust.ai-trust.msp
setup_kcp >/dev/null 2>&1; kcp_portforward >/dev/null 2>&1; trap 'pkill -f "port-forward.*root-proxy.*6443" 2>/dev/null||true' EXIT
kc "$PROVIDER_WS" get apiresourceschema "$SCH" -o json 2>&1 | grep -av memcache \
  | python3 -c "
import sys,json
d=json.load(sys.stdin)
sch=d['spec']['versions'][0]['schema']
# look for x-kubernetes-preserve-unknown-fields, missing types, additionalProperties, empty objects
def walk(o,path='root'):
    issues=[]
    if isinstance(o,dict):
        if o.get('type')=='object' and 'properties' not in o and 'additionalProperties' not in o and not o.get('x-kubernetes-preserve-unknown-fields'):
            issues.append(f'{path}: object with NO properties (gateway may name it undefined)')
        if o.get('x-kubernetes-preserve-unknown-fields'):
            issues.append(f'{path}: x-kubernetes-preserve-unknown-fields=true')
        if 'type' not in o and 'properties' not in o and path!='root' and not o.get('x-kubernetes-preserve-unknown-fields'):
            issues.append(f'{path}: NO type field')
        for k,v in o.get('properties',{}).items():
            issues+=walk(v,path+'.'+k)
    return issues
for i in walk(sch): print(i)
print('--- status subtree keys:', list(sch.get('properties',{}).get('status',{}).keys()))
print('--- status props:', list(sch.get('properties',{}).get('status',{}).get('properties',{}).keys()))
"
