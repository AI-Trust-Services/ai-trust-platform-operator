#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
OUT="$STATE/checkd-content.json"
: > "$OUT"
for i in 1 2 3; do
  sk -n platform-mesh-system run cd$i-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet -- \
    curl -sS http://aitrust-portal.aitrust-msp.svc.cluster.local/pm-content.json 2>/dev/null > "$OUT"
  [ -s "$OUT" ] && break; sleep 3
done
echo "fetched $(wc -c < "$OUT") bytes"
python3 <<'PY'
import json
d=json.load(open("/mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP/.state/checkd-content.json"))
nodes=d["luigiConfigFragment"]["data"]["nodes"]
def walk(ns):
    for n in ns:
        yield n
        for c in n.get("children",[]) or []:
            yield from walk([c])
found=None
for n in walk(nodes):
    rd=(n.get("context") or {}).get("resourceDefinition")
    if rd and rd.get("kind")=="AITrustPlatformInstance":
        found=(n,rd); break
if not found:
    # fall back to first node with any resourceDefinition
    for n in walk(nodes):
        rd=(n.get("context") or {}).get("resourceDefinition")
        if rd:
            found=(n,rd); break
n,rd=found
print("=== CHECK D ===")
print("group   =", rd.get("group"))
print("version =", rd.get("version"))
print("kind    =", rd.get("kind"))
print("plural  =", rd.get("plural"))
cv=(rd.get("ui") or {}).get("createView")
# createView may be a dict with fields, or a list; find first field
first=None
if isinstance(cv,dict):
    flds=cv.get("fields") or cv.get("elements") or cv.get("form")
    if isinstance(flds,list) and flds:
        f0=flds[0]
        first=f0.get("path") or f0.get("name") or f0.get("jsonPath") or f0
    else:
        first=cv
elif isinstance(cv,list) and cv:
    f0=cv[0]
    first=f0.get("path") or f0.get("name") or f0.get("jsonPath") or f0 if isinstance(f0,dict) else f0
print("createView raw =", json.dumps(cv)[:600])
print("createView first field =", json.dumps(first)[:200])
PY
