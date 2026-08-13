#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
echo "=== hit the users list endpoint from inside the cluster + capture the error ==="
POD=$(kubectl -n "$NS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep '^users-backend-' | grep Running | awk '{print $1}' | head -1)
echo "pod: $POD"
# reproduce the token+list call the app does, print status + body
kubectl -n "$NS" exec "$POD" -- sh -lc '
python - <<PY 2>&1 | head -30
import os, httpx
KC=os.environ["KEYCLOAK_URL"]; R=os.environ["KEYCLOAK_REALM"]
cid=os.environ["USERS_BACKEND_CLIENT_ID"]; sec=os.environ["USERS_BACKEND_CLIENT_SECRET"]
t=httpx.post(f"{KC}/realms/{R}/protocol/openid-connect/token",data={"grant_type":"client_credentials","client_id":cid,"client_secret":sec},timeout=10)
print("token http", t.status_code, "" if t.status_code==200 else t.text[:200])
if t.status_code==200:
    tok=t.json()["access_token"]
    u=httpx.get(f"{KC}/admin/realms/{R}/users?max=10",headers={"Authorization":f"Bearer {tok}"},timeout=10)
    print("list-users http", u.status_code, "" if u.status_code==200 else u.text[:300])
    print("count:", len(u.json()) if u.status_code==200 else "-")
PY
' 2>&1 | grep -avi memcache | head -20
echo "=== fresh users-backend log tail (the /users 500 traceback) ==="
kubectl -n "$NS" logs "$POD" --tail=40 2>&1 | grep -avi memcache | grep -iE 'error|exception|traceback|realm|forbidden|403|users|custom_roles|Undefined' | tail -15
echo DONE
