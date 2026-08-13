#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
echo "=== operator image + env ==="
kubectl -n "$NS" get deploy aitrust-mt-operator -o jsonpath='image={.spec.template.spec.containers[0].image}{"\n"}sa={.spec.template.spec.serviceAccountName}{"\n"}' 2>&1 | grep -avi memcache
kubectl -n "$NS" get deploy aitrust-mt-operator -o jsonpath='{range .spec.template.spec.containers[0].env[*]}{"  env "}{.name}={.value}{"\n"}{end}' 2>&1 | grep -avi memcache
echo "=== operator ClusterRole (exact name from its binding) ==="
SA=$(kubectl -n "$NS" get deploy aitrust-mt-operator -o jsonpath='{.spec.template.spec.serviceAccountName}' 2>&1 | grep -avi memcache)
# find bindings referencing this SA in this ns
kubectl get clusterrolebinding -o json 2>/dev/null | grep -avi memcache > /tmp/crb.json
python3 - <<PY 2>&1 | grep -avi memcache
import json
d=json.load(open("/tmp/crb.json"))
sa="$SA"; ns="$NS"
for it in d.get("items",[]):
    subs=it.get("subjects") or []
    for s in subs:
        if s.get("kind")=="ServiceAccount" and s.get("name")==sa and s.get("namespace",ns)==ns:
            print("binding:",it["metadata"]["name"],"-> role",it["roleRef"]["name"])
PY
echo "=== also Roles in ns bound to it ==="
kubectl -n "$NS" get rolebinding -o json 2>/dev/null | grep -avi memcache > /tmp/rb.json
python3 - <<PY 2>&1 | grep -avi memcache
import json
d=json.load(open("/tmp/rb.json"))
sa="$SA"
for it in d.get("items",[]):
    for s in (it.get("subjects") or []):
        if s.get("kind")=="ServiceAccount" and s.get("name")==sa:
            print("rolebinding:",it["metadata"]["name"],"-> role",it["roleRef"]["kind"],it["roleRef"]["name"])
PY
echo DONE
