#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp; GWNS=platform-mesh-system
SECRET="aitrust-mt-users-backend-secret"
KC_INT="http://keycloak-service.$GWNS.svc.cluster.local:8080/keycloak"
echo "== repoint users-backend at mesh poc2 =="
kubectl -n "$NS" set env deploy/users-backend \
  KEYCLOAK_URL="$KC_INT" \
  KEYCLOAK_REALM="poc2" \
  USERS_BACKEND_CLIENT_ID="users-backend" \
  USERS_BACKEND_CLIENT_SECRET="$SECRET" 2>&1 | grep -avi memcache
kubectl -n "$NS" rollout status deploy/users-backend --timeout=120s 2>&1 | grep -avi memcache | tail -1
echo "== verify env now =="
kubectl -n "$NS" get deploy users-backend -o jsonpath='{range .spec.template.spec.containers[0].env[*]}{.name}={.value}{"\n"}{end}' 2>&1 | grep -avi memcache | grep -iE 'KEYCLOAK|USERS_BACKEND_CLIENT_ID|OPENFGA_STORE'
echo "== verify: users-backend can now list users from poc2 (in-cluster token + admin API) =="
POD=$(kubectl -n "$NS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep '^users-backend-' | grep Running | awk '{print $1}' | head -1)
echo "pod: $POD"
kubectl -n "$NS" exec "$POD" -- sh -lc '
python - <<PY 2>&1 | head -20
import os, httpx
KC=os.environ["KEYCLOAK_URL"]; R=os.environ["KEYCLOAK_REALM"]
cid=os.environ["USERS_BACKEND_CLIENT_ID"]; sec=os.environ["USERS_BACKEND_CLIENT_SECRET"]
t=httpx.post(f"{KC}/realms/{R}/protocol/openid-connect/token",data={"grant_type":"client_credentials","client_id":cid,"client_secret":sec},timeout=10)
print("token http", t.status_code)
tok=t.json()["access_token"]
u=httpx.get(f"{KC}/admin/realms/{R}/users?max=5",headers={"Authorization":f"Bearer {tok}"},timeout=10)
print("users http", u.status_code, "count_returned", len(u.json()) if u.status_code==200 else u.text[:120])
for usr in (u.json() if u.status_code==200 else []): print("  user:", usr.get("username"))
PY
' 2>&1 | grep -avi memcache | head -20
echo DONE
