#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
setup_kcp >/dev/null 2>&1
trap 'pkill -f "port-forward.*root-proxy.*6443" 2>/dev/null||true' EXIT
pkill -f "port-forward.*root-proxy.*6443" 2>/dev/null || true; sleep 1
sk -n "$MESH_NS" port-forward svc/root-proxy 6443:6443 >/tmp/pf.log 2>&1 &
for i in $(seq 1 30); do kc "$PROVIDER_WS" get apiexport >/dev/null 2>&1 && { echo "pf ready ${i}s"; break; }; sleep 1; done

kc "$PROVIDER_WS" get apiexport trust.aitrust.msp -o json 2>&1 | grep -av memcache > /tmp/ae.json
echo "=== raw spec of the APIExport (which field lists the schema) ==="
python3 -c "
import json
d=json.load(open('/tmp/ae.json'))
print('spec keys:', list(d.get('spec',{}).keys()))
print(json.dumps(d.get('spec',{}), indent=2))
"
