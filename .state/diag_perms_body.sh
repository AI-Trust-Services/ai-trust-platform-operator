#!/bin/bash
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh 2>/dev/null; load_config 2>/dev/null
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
f(){ grep -avi memcache; }

PYEXPR='import urllib.request,json
url="http://localhost:8008/v1/me/permissions"
req=urllib.request.Request(url,headers={"X-Forwarded-Preferred-Username":"mircea.craciun@sap.com"})
r=urllib.request.urlopen(req,timeout=5)
print("status",r.status)
body=r.read().decode()
print(body[:1200])
try:
    d=json.loads(body); print("PERMISSION COUNT =", len(d.get("permissions",[])))
except Exception as e: print("parse err",e)'
echo "===== users-backend self-call /v1/me/permissions on :8008 (preferred_username = the real user) ====="
kubectl -n "$NS" exec deploy/users-backend -- python -c "$PYEXPR" 2>&1 | f

echo; echo "===== same, but simulating the UUID fallback (what happens if preferred_username were absent) ====="
PYEXPR2='import urllib.request,json
url="http://localhost:8008/v1/me/permissions"
req=urllib.request.Request(url,headers={"X-Forwarded-User":"b0a037bf-7782-4ad6-9043-18f6cb123c05"})
try:
    r=urllib.request.urlopen(req,timeout=5); d=json.loads(r.read().decode())
    print("status",r.status,"PERMISSION COUNT =",len(d.get("permissions",[])))
except Exception as e: print("err",e)'
kubectl -n "$NS" exec deploy/users-backend -- python -c "$PYEXPR2" 2>&1 | f
echo DONE
