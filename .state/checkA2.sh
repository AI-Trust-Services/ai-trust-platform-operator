#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
setup_kcp >/dev/null 2>&1
trap 'pkill -f "port-forward.*root-proxy.*6443" 2>/dev/null||true' EXIT

# robust port-forward + wait until it answers
pkill -f "port-forward.*root-proxy.*6443" 2>/dev/null || true; sleep 1
sk -n "$MESH_NS" port-forward svc/root-proxy 6443:6443 >/tmp/pf-kcp-aitrust.log 2>&1 &
for i in $(seq 1 30); do
  if kc root get workspaces >/dev/null 2>&1 || kc "$PROVIDER_WS" get apiexport >/dev/null 2>&1; then
    echo "port-forward ready after ${i}s"; break
  fi
  sleep 1
done

NEW_EXPORT=trust.aitrust.msp
NEW_SCH=vbd3d9af8.aitrustplatforminstances.trust.aitrust.msp

echo "############ (1) APIExport ${NEW_EXPORT} in ${PROVIDER_WS} ############"
kc "$PROVIDER_WS" get apiexport "$NEW_EXPORT" -o json 2>/tmp/e1.txt | grep -av memcache > /tmp/ae.json
if [ -s /tmp/ae.json ]; then
python3 -c "
import sys,json
d=json.load(open('/tmp/ae.json'))
print('name        :', d['metadata']['name'])
sp=d.get('spec',{})
res=sp.get('latestResourceSchemas', sp.get('resourceSchemas',[]))
print('latestResourceSchemas:')
for r in res: print('   -', r)
st=d.get('status',{})
print('status.conditions:')
for c in st.get('conditions',[]):
    print('   -', c.get('type'), '=', c.get('status'), c.get('reason',''), c.get('message','')[:80])
print('identityHash present:', bool(st.get('identityHash')))
# resources served
print('status.resourceSchemas / virtualWorkspaces present keys:', [k for k in st.keys()])
"
else
  echo "ERROR fetching apiexport:"; cat /tmp/e1.txt
fi

echo ""
echo "############ (2) APIResourceSchema ${NEW_SCH} ############"
kc "$PROVIDER_WS" get apiresourceschema "$NEW_SCH" -o json 2>/tmp/e2.txt | grep -av memcache > /tmp/ars.json
if [ -s /tmp/ars.json ]; then
python3 -c "
import sys,json
d=json.load(open('/tmp/ars.json'))
sp=d['spec']
print('schema name :', d['metadata']['name'])
print('group       :', sp.get('group'))
names=sp.get('names',{})
print('kind        :', names.get('kind'))
print('plural      :', names.get('plural'), ' singular:', names.get('singular'))
vers=sp.get('versions',[])
for v in vers:
    print('version     :', v.get('name'), 'served=', v.get('served'), 'storage=', v.get('storage'))
v0=vers[0]
scho=v0.get('schema',{})
sch=scho.get('openAPIV3Schema', scho)
props=sch.get('properties',{})
print('top-level props:', list(props.keys()))
status=props.get('status',{})
def find_preserve(o,path):
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
print('status.props:', list(status.get('properties',{}).keys()))
print('status x-kubernetes-preserve-unknown-fields:', find_preserve(status,'status') or 'NONE')
print('preserve-unknown ANYWHERE in schema:', find_preserve(sch,'root') or 'NONE')
"
else
  echo "ERROR fetching apiresourceschema:"; cat /tmp/e2.txt
fi

echo ""
echo "############ (3) Old-group residue check (trust.ai-trust.msp) ############"
echo "-- FULL apiexports in ${PROVIDER_WS}:"
kc "$PROVIDER_WS" get apiexport -o name 2>&1 | grep -av memcache
echo "-- FULL apiresourceschemas in ${PROVIDER_WS}:"
kc "$PROVIDER_WS" get apiresourceschema -o name 2>&1 | grep -av memcache
echo "-- old-group (ai-trust.msp) matches above? filter:"
{ kc "$PROVIDER_WS" get apiexport -o name 2>&1; kc "$PROVIDER_WS" get apiresourceschema -o name 2>&1; } | grep -av memcache | grep -i 'ai-trust\.msp' || echo "   (NONE — no hyphenated group residue)"
echo ""
echo "-- consumer ws root:orgs:aitrustg2:demo apibindings:"
kc root:orgs:aitrustg2:demo get apibinding -o json 2>/tmp/e3.txt | grep -av memcache > /tmp/ab.json
if [ -s /tmp/ab.json ]; then
python3 -c "
import json
d=json.load(open('/tmp/ab.json'))
for it in d.get('items',[]):
    ref=it.get('spec',{}).get('reference',{}).get('export',{})
    print('   binding', it['metadata']['name'], '-> export', ref.get('name'), 'ws', ref.get('path'), '| phase', it.get('status',{}).get('phase'))
    for r in it.get('status',{}).get('boundResources',[]):
        print('       boundResource group=', r.get('group'), 'resource=', r.get('resource'))
"
else
  echo "   (no apibindings / error)"; cat /tmp/e3.txt
fi
