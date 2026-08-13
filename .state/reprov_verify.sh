#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
echo "=== ensure compliance-backend is up + all client pods running ==="
kubectl -n "$NS" scale deploy/compliance-backend --replicas=1 >/dev/null 2>&1
kubectl -n "$NS" get deploy -o wide 2>/dev/null | grep -avi memcache | grep -E 'backend|worker|consumer|rmq' | awk '{printf "%-40s %s\n",$1,$2}'
echo "=== users + custom-roles endpoints (the ones that 500'd) via users-backend ==="
sleep 8
POD=$(kubectl -n "$NS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep '^users-backend-' | grep Running | awk '{print $1}' | head -1)
kubectl -n "$NS" exec "$POD" -- sh -lc '
python - <<PY 2>&1 | head
import httpx
for p in ["/v1/iam/custom-roles","/v1/users?limit=10&offset=0"]:
    r=httpx.get("http://localhost:8008"+p, headers={"X-Forwarded-Preferred-Username":"mircea.craciun@sap.com"}, timeout=10)
    print(p,"->",r.status_code, "OK" if r.status_code<400 else r.text[:100])
PY' 2>&1 | grep -avi memcache | head
echo "=== registry systems endpoint (proves RLS/tenant path healthy) ==="
RPOD=$(kubectl -n "$NS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep '^ai-system-registry-backend-' | grep Running | awk '{print $1}' | head -1)
kubectl -n "$NS" exec "$RPOD" -- sh -lc 'python - <<PY 2>&1 | head
import httpx
r=httpx.get("http://localhost:8001/v1/systems?limit=5", headers={"X-Forwarded-Preferred-Username":"mircea.craciun@sap.com"}, timeout=10)
print("/v1/systems ->", r.status_code, "OK" if r.status_code<400 else r.text[:100])
PY' 2>&1 | grep -avi memcache | head
echo DONE
