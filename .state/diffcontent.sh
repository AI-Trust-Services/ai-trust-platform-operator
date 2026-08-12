#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
for i in 1 2 3; do
  sk -n platform-mesh-system run mc$i-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet -- \
    curl -sS http://aitrust-portal.aitrust-msp.svc.cluster.local/pm-content.json 2>/dev/null > "$STATE/mine-content.json"
  [ -s "$STATE/mine-content.json" ] && break; sleep 3
done
echo "fetched $(wc -c < "$STATE/mine-content.json") bytes"
python3 <<'PY'
import json
mine=json.load(open("/mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP/.state/mine-content.json"))
pll=json.load(open("/mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP/.state/pll-content.json"))
mn=mine["luigiConfigFragment"]["data"]["nodes"][0]
pn=pll["luigiConfigFragment"]["data"]["nodes"][0]
def k(o): return set(o.keys())
print("NODE keys  mine-only:",k(mn)-k(pn)," work-only:",k(pn)-k(mn))
mrd=mn["context"]["resourceDefinition"]; prd=pn["context"]["resourceDefinition"]
print("RD keys    mine-only:",k(mrd)-k(prd)," work-only:",k(prd)-k(mrd))
print("mine url:",mn.get("url"))
print("work url:",pn.get("url"))
print("mine webcomponent:",mn.get("webcomponent"))
print("work webcomponent:",pn.get("webcomponent"))
print("mine has children:", 'children' in mn, "| work has children:", 'children' in pn)
PY
