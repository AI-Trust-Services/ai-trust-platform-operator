#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
echo "=== overview-backend recent request logs (status codes on /api/overview) ==="
kubectl -n "$NS" logs deploy/overview-backend --tail=40 2>&1 | grep -avi memcache | grep -iE 'tenant|401|500|request.completed|request.client_error|error|unresolved' | tail -20
echo "=== users-backend (me/permissions) ==="
kubectl -n "$NS" logs deploy/users-backend --tail=30 2>&1 | grep -avi memcache | grep -iE 'tenant|401|500|permissions|unresolved|error' | tail -12
echo "=== does the mirceatest token carry tenant_id? decode the resolver path: check JWKS reachability from a backend ==="
kubectl -n "$NS" exec deploy/overview-backend -- sh -lc '
python - <<PY 2>&1 | head -20
import os, urllib.request, json
base=os.environ.get("TENANCY_JWKS_ISSUER_BASE","")
iss=base+"/mirceatest"
url=iss+"/protocol/openid-connect/certs"
print("JWKS url:", url)
try:
    with urllib.request.urlopen(url, timeout=8) as r:
        d=json.load(r); print("JWKS reachable, keys:", len(d.get("keys",[])))
except Exception as e:
    print("JWKS FETCH FAILED:", repr(e)[:200])
PY
' 2>&1 | grep -avi memcache | head -20
echo DONE
