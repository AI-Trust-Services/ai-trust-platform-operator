#!/bin/bash
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh 2>/dev/null; load_config 2>/dev/null
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
f(){ grep -avi memcache; }

# Mint short-lived token via keycloak-0 kcadm, then use curl pod to set post.logout.redirect.uris to
# cover BOTH the bare origin and origin/* and the callback, then verify.
KCU=$(kubectl -n "$NS" get secret mesh-keycloak-admin -o jsonpath='{.data.username}' | base64 -d)
KCP=$(kubectl -n "$NS" get secret mesh-keycloak-admin -o jsonpath='{.data.password}' | base64 -d)
TOKINNER='K=/opt/keycloak/bin/kcadm.sh
$K config credentials --server http://localhost:8080/keycloak --realm master --user "$U" --password "$P" >/dev/null 2>&1
cat ~/.keycloak/kcadm.config 2>/dev/null | grep -oE "\"token\" : \"[^\"]*\"" | head -1 | sed "s/\"token\" : \"//;s/\"//"'
TOKEN=$(kubectl -n platform-mesh-system exec -i keycloak-0 -- env U="$KCU" P="$KCP" sh -c "$TOKINNER" 2>/dev/null | grep -avi memcache | tr -d "[:space:]")
[ -n "$TOKEN" ] && echo "token len=${#TOKEN}" || { echo "TOKEN FAIL"; exit 1; }

KC=http://keycloak-service.platform-mesh-system.svc.cluster.local:8080/keycloak
ORIGIN="https://ai-trust-mt-fridaytest.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu"
# post.logout.redirect.uris supports "##"-delimited multiple values in Keycloak. Cover bare origin, origin/*, and callback.
PLV="$ORIGIN##$ORIGIN/*"
INNER='AUTH="Authorization: Bearer $TOKEN"
ID=$(curl -s -H "$AUTH" "$KC/admin/realms/fridaytest/clients?clientId=aitrust-mt-app" | grep -oE "\"id\":\"[^\"]*\"" | head -1 | sed "s/\"id\":\"//;s/\"//")
echo "client id: $ID"
echo "-- current redirectUris + post.logout --"
curl -s -H "$AUTH" "$KC/admin/realms/fridaytest/clients/$ID" | grep -oE "\"redirectUris\":\[[^]]*\]|post.logout.redirect.uris\":\"[^\"]*\""
# GET full rep, set attribute via sed, PUT
curl -s -H "$AUTH" "$KC/admin/realms/fridaytest/clients/$ID" > /tmp/c.json
if grep -q "post.logout.redirect.uris" /tmp/c.json; then
  sed "s#post.logout.redirect.uris\":\"[^\"]*\"#post.logout.redirect.uris\":\"$PLV\"#" /tmp/c.json > /tmp/c2.json
else
  sed "s#\"attributes\":{#\"attributes\":{\"post.logout.redirect.uris\":\"$PLV\",#" /tmp/c.json > /tmp/c2.json
fi
H=$(curl -s -o /tmp/put.out -w "%{http_code}" -X PUT -H "$AUTH" -H "Content-Type: application/json" "$KC/admin/realms/fridaytest/clients/$ID" -d @/tmp/c2.json)
echo "PUT: $H"; [ "$H" = "204" ] || cat /tmp/put.out
echo "-- verify --"
curl -s -H "$AUTH" "$KC/admin/realms/fridaytest/clients/$ID" | grep -oE "post.logout.redirect.uris\":\"[^\"]*\""'
kubectl -n "$NS" run plfix-$$ --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet \
  --env="TOKEN=$TOKEN" --env="KC=$KC" --env="PLV=$PLV" --command -- sh -c "$INNER" 2>&1 | f
echo DONE
