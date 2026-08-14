#!/bin/bash
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh 2>/dev/null; load_config 2>/dev/null
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
f(){ grep -avi memcache; }

echo "===== users-backend Keycloak env (which realm does IAM manage?) ====="
kubectl -n "$NS" get deploy users-backend -o jsonpath='{range .spec.template.spec.containers[0].env[*]}{.name}={.value}{"\n"}{end}' 2>&1 | f | grep -iE 'KEYCLOAK_URL|KEYCLOAK_REALM|USERS_BACKEND_CLIENT_ID|USERS_BACKEND_CLIENT_SECRET' | sed 's/SECRET=.*/SECRET=<redacted>/'

echo; echo "===== where did mircea@mircea.com actually land? check the KEYCLOAK_REALM realm's users ====="
KCU=$(kubectl -n "$NS" get secret mesh-keycloak-admin -o jsonpath='{.data.username}' | base64 -d)
KCP=$(kubectl -n "$NS" get secret mesh-keycloak-admin -o jsonpath='{.data.password}' | base64 -d)
REALM=$(kubectl -n "$NS" get deploy users-backend -o jsonpath='{range .spec.template.spec.containers[0].env[?(@.name=="KEYCLOAK_REALM")]}{.value}{end}' 2>/dev/null)
REALM=${REALM:-ai-trust}
echo "  KEYCLOAK_REALM in use = $REALM"
INNER='K=/opt/keycloak/bin/kcadm.sh
$K config credentials --server http://localhost:8080/keycloak --realm master --user "$U" --password "$P" >/dev/null 2>&1
echo "=== realms present in mesh Keycloak ==="
$K get realms --fields realm 2>/dev/null | grep -oE "\"realm\" : \"[^\"]*\"" | head -40
echo "=== users in realm '"$R"' ==="
$K get users -r "$R" --fields username,email 2>/dev/null || echo "  (realm $R not found or no access)"'
kubectl -n platform-mesh-system exec -i keycloak-0 -- env U="$KCU" P="$KCP" R="$REALM" sh -c "$INNER" 2>&1 | f
echo DONE
