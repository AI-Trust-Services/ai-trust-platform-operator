#!/bin/bash
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh 2>/dev/null; load_config 2>/dev/null
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
f(){ grep -avi memcache; }

# What issuer base does the tenancy middleware demand, per backend?
echo "===== TENANCY_JWKS_ISSUER_BASE expected by each backend ====="
for D in users-backend compliance-backend ai-system-registry-backend; do
  V=$(kubectl -n "$NS" get deploy "$D" -o jsonpath='{range .spec.template.spec.containers[0].env[?(@.name=="TENANCY_JWKS_ISSUER_BASE")]}{.value}{end}' 2>/dev/null)
  echo "  $D : ${V:-<unset>}"
done

echo; echo "===== decode iss + tenant_id from a REAL token for fridaytest AND mirceatest ====="
# get the aitrust-mt-app client secret per realm from KC (inside keycloak-0, no secrets to argv),
# do a direct-grant as the app client using the mesh admin? No — simpler: mint tokens via the
# app client with a password grant is not possible without the user password.
# Instead: read the token issuer config directly from KC realm settings (frontendUrl / issuer),
# which is what Keycloak stamps as `iss`.
KCU=$(kubectl -n "$NS" get secret mesh-keycloak-admin -o jsonpath='{.data.username}' | base64 -d)
KCP=$(kubectl -n "$NS" get secret mesh-keycloak-admin -o jsonpath='{.data.password}' | base64 -d)
INNER='K=/opt/keycloak/bin/kcadm.sh
$K config credentials --server http://localhost:8080/keycloak --realm master --user "$U" --password "$P" >/dev/null 2>&1
for R in fridaytest mirceatest; do
  echo "--- realm $R : frontendUrl / issuer-affecting settings ---"
  $K get realms/$R --fields realm,frontendUrl,attributes 2>/dev/null | grep -iE "realm|frontendUrl|frontend"
  echo "    (token iss will be: <server-baseurl-or-frontendUrl>/realms/$R)"
done'
kubectl -n platform-mesh-system exec -i keycloak-0 -- env U="$KCU" P="$KCP" sh -c "$INNER" 2>&1 | f

echo; echo "===== what public hostname does KC think it has? (KC_HOSTNAME / frontend) ====="
kubectl -n platform-mesh-system get statefulset keycloak -o jsonpath='{range .spec.template.spec.containers[0].env[*]}{.name}={.value}{"\n"}{end}' 2>&1 | f | grep -iE 'HOSTNAME|FRONTEND|PROXY|URL' | head -20
echo DONE
