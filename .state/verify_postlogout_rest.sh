#!/bin/bash
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh 2>/dev/null; load_config 2>/dev/null
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
f(){ grep -avi memcache; }

KCU=$(kubectl -n "$NS" get secret mesh-keycloak-admin -o jsonpath='{.data.username}' | base64 -d)
KCP=$(kubectl -n "$NS" get secret mesh-keycloak-admin -o jsonpath='{.data.password}' | base64 -d)
TOKINNER='K=/opt/keycloak/bin/kcadm.sh
$K config credentials --server http://localhost:8080/keycloak --realm master --user "$U" --password "$P" >/dev/null 2>&1
cat ~/.keycloak/kcadm.config 2>/dev/null | grep -oE "\"token\" : \"[^\"]*\"" | head -1 | sed "s/\"token\" : \"//;s/\"//"'
TOKEN=$(kubectl -n platform-mesh-system exec -i keycloak-0 -- env U="$KCU" P="$KCP" sh -c "$TOKINNER" 2>/dev/null | grep -avi memcache | tr -d "[:space:]")
[ -n "$TOKEN" ] && echo "token len=${#TOKEN}" || { echo "TOKEN FAIL"; exit 1; }

KC=http://keycloak-service.platform-mesh-system.svc.cluster.local:8080/keycloak
INNER='AUTH="Authorization: Bearer $TOKEN"
for R in fridaytest livedemo mirceatest mttest2 sohan; do
  ID=$(curl -s -H "$AUTH" "$KC/admin/realms/$R/clients?clientId=aitrust-mt-app" | grep -oE "\"id\":\"[^\"]*\"" | head -1 | sed "s/\"id\":\"//;s/\"//")
  PL=$(curl -s -H "$AUTH" "$KC/admin/realms/$R/clients/$ID" | grep -oE "post.logout.redirect.uris\":\"[^\"]*\"" || echo "MISSING")
  echo "  $R: $PL"
done'
kubectl -n "$NS" run plcheck-$$ --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet \
  --env="TOKEN=$TOKEN" --env="KC=$KC" --command -- sh -c "$INNER" 2>&1 | f
echo DONE
