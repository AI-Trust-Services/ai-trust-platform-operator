#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
echo "=== current pm-content.json createView fields ==="
kubectl -n "$NS" get cm aitrust-mt-portal-config -o jsonpath='{.data.pm-content\.json}' 2>&1 | grep -avi memcache | grep -iE 'spec.org|createView|Display Name|Admin Email' | head
echo "=== inject the Org field into the live ConfigMap (add after Display Name in createView) ==="
kubectl -n "$NS" get cm aitrust-mt-portal-config -o jsonpath='{.data.pm-content\.json}' 2>/dev/null | grep -avi memcache > /tmp/pm.json
python3 - <<'PY' 2>&1 | grep -avi memcache
import json
d=json.load(open("/tmp/pm.json"))
# navigate to createView.fields
node=d["luigiConfigFragment"]["data"]["nodes"][0]
cv=node["context"]["resourceDefinition"]["ui"]["createView"]["fields"]
if not any(f.get("property")=="spec.org" for f in cv):
    # insert after Display Name
    idx=next((i for i,f in enumerate(cv) if f.get("property")=="spec.displayName"), 0)
    cv.insert(idx+1, {"label":"Org (mesh realm)","property":"spec.org","required":True})
lv=node["context"]["resourceDefinition"]["ui"]["listView"]["fields"]
if not any(f.get("property")=="spec.org" for f in lv):
    lv.insert(2, {"label":"Org","property":"spec.org"})
open("/tmp/pm2.json","w").write(json.dumps(d))
print("org field present in createView:", any(f.get("property")=="spec.org" for f in cv))
PY
# patch the CM data key
kubectl -n "$NS" create cm aitrust-mt-portal-config --from-file=pm-content.json=/tmp/pm2.json --dry-run=client -o yaml 2>&1 | grep -avi memcache | kubectl apply -f - 2>&1 | grep -avi memcache
echo "=== restart portal-integration nginx ==="
kubectl -n "$NS" rollout restart deploy/aitrust-mt-portal-integration 2>&1 | grep -avi memcache
kubectl -n "$NS" rollout status deploy/aitrust-mt-portal-integration --timeout=90s 2>&1 | grep -avi memcache | tail -1
echo "=== verify served content has spec.org ==="
kubectl -n "$NS" get cm aitrust-mt-portal-config -o jsonpath='{.data.pm-content\.json}' 2>&1 | grep -avi memcache | grep -o 'spec.org' | head -1
echo DONE
