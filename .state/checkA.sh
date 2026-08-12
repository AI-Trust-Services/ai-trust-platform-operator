#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
setup_kcp >/dev/null 2>&1; kcp_portforward >/dev/null 2>&1
trap 'pkill -f "port-forward.*root-proxy.*6443" 2>/dev/null||true' EXIT

NEW_EXPORT=trust.aitrust.msp
NEW_SCH=vbd3d9af8.aitrustplatforminstances.trust.aitrust.msp
OLD_EXPORT=trust.ai-trust.msp

echo "############ (1) APIExport ${NEW_EXPORT} in ${PROVIDER_WS} ############"
kc "$PROVIDER_WS" get apiexport "$NEW_EXPORT" -o json 2>&1 | grep -av memcache \
  | python3 -c "
import sys,json
d=json.load(sys.stdin)
print('name        :', d['metadata']['name'])
sp=d.get('spec',{})
res=sp.get('latestResourceSchemas', sp.get('resourceSchemas',[]))
print('latestResourceSchemas:')
for r in res: print('   -', r)
# status: which schemas are actually being served / identity
st=d.get('status',{})
print('status.conditions:')
for c in st.get('conditions',[]):
    print('   -', c.get('type'), '=', c.get('status'), c.get('reason',''), c.get('message','')[:80])
print('identity hash present:', bool(st.get('identityHash')))
"

echo ""
echo "############ (2) APIResourceSchema ${NEW_SCH} ############"
kc "$PROVIDER_WS" get apiresourceschema "$NEW_SCH" -o json 2>&1 | grep -av memcache \
  | python3 -c "
import sys,json
d=json.load(sys.stdin)
sp=d['spec']
print('schema name :', d['metadata']['name'])
print('group       :', sp.get('group'))
names=sp.get('names',{})
print('kind        :', names.get('kind'))
print('plural      :', names.get('plural'), ' singular:', names.get('singular'))
vers=sp.get('versions',[])
for v in vers:
    print('version     :', v.get('name'), 'served=', v.get('served'), 'storage=', v.get('storage'))
# status subtree preserve-unknown check
v0=vers[0]
sch=v0['schema']['openAPIV3Schema'] if 'openAPIV3Schema' in v0.get('schema',{}) else v0.get('schema',{})
props=sch.get('properties',{})
print('top-level props:', list(props.keys()))
status=props.get('status',{})
def find_preserve(o,path='status'):
    hits=[]
    if isinstance(o,dict):
        if o.get('x-kubernetes-preserve-unknown-fields'):
            hits.append(path)
        for k,v in o.get('properties',{}).items():
            hits+=find_preserve(v,path+'.'+k)
        ap=o.get('additionalProperties')
        if isinstance(ap,dict):
            hits+=find_preserve(ap,path+'.<addl>')
    return hits
sp_hits=find_preserve(status)
print('status.props:', list(status.get('properties',{}).keys()))
print('status x-kubernetes-preserve-unknown-fields locations:', sp_hits if sp_hits else 'NONE')
# also check whole schema for preserve at root/spec (informational)
allhits=find_preserve(sch,'root')
print('preserve-unknown ANYWHERE:', allhits if allhits else 'NONE')
"

echo ""
echo "############ (3) Old-group residue check (trust.ai-trust.msp) ############"
echo "-- APIExports matching old group in ${PROVIDER_WS}:"
kc "$PROVIDER_WS" get apiexport -o name 2>&1 | grep -av memcache | grep -i 'ai-trust.msp' || echo "   (none)"
echo "-- APIResourceSchemas matching old group in ${PROVIDER_WS}:"
kc "$PROVIDER_WS" get apiresourceschema -o name 2>&1 | grep -av memcache | grep -i 'ai-trust.msp' || echo "   (none)"
echo ""
echo "-- FULL list of apiexports in ${PROVIDER_WS}:"
kc "$PROVIDER_WS" get apiexport -o name 2>&1 | grep -av memcache
echo "-- FULL list of apiresourceschemas in ${PROVIDER_WS}:"
kc "$PROVIDER_WS" get apiresourceschema -o name 2>&1 | grep -av memcache
echo ""
echo "-- Check consumer ws root:orgs:aitrustg2:demo for old-group bindings/exports:"
kc root:orgs:aitrustg2:demo get apibinding -o name 2>&1 | grep -av memcache
echo "   apibinding detail (group + state):"
kc root:orgs:aitrustg2:demo get apibinding -o json 2>&1 | grep -av memcache \
  | python3 -c "
import sys,json
d=json.load(sys.stdin)
for it in d.get('items',[]):
    ref=it.get('spec',{}).get('reference',{}).get('export',{})
    print('   binding', it['metadata']['name'], '-> export', ref.get('name'), 'ws', ref.get('path'), '| phase', it.get('status',{}).get('phase'))
" 2>&1
