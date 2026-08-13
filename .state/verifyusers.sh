#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
echo "=== call both endpoints from in-cluster (via the users-backend directly) ==="
POD=$(kubectl -n "$NS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep '^users-backend-' | grep Running | awk '{print $1}' | head -1)
kubectl -n "$NS" exec "$POD" -- sh -lc '
python - <<PY 2>&1 | head -20
import httpx
b="http://localhost:8008"
for path in ["/api/users/v1/iam/custom-roles","/api/users/v1/users?limit=10&offset=0"]:
    try:
        # ROOT_PATH is /api/users so hit the raw route on 8008 without prefix:
        p=path.replace("/api/users","")
        r=httpx.get(b+p, headers={"X-Forwarded-Preferred-Username":"mircea.craciun@sap.com"}, timeout=10)
        print(path, "->", r.status_code, (r.text[:120] if r.status_code>=400 else "OK"))
    except Exception as e:
        print(path, "ERR", str(e)[:120])
PY
' 2>&1 | grep -avi memcache | head -12
echo "=== recent users-backend log (any NEW 500 after table create?) ==="
kubectl -n "$NS" logs "$POD" --since=2m 2>&1 | grep -avi memcache | grep -iE 'status.*500|error|Undefined|custom_roles' | tail -8
echo "(empty above = no new errors)"
echo DONE
