#!/bin/bash
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh 2>/dev/null; load_config 2>/dev/null
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
f(){ grep -avi memcache; }

KCU=$(kubectl -n "$NS" get secret mesh-keycloak-admin -o jsonpath='{.data.username}' | base64 -d)
KCP=$(kubectl -n "$NS" get secret mesh-keycloak-admin -o jsonpath='{.data.password}' | base64 -d)

# Mint a short-lived admin token INSIDE keycloak-0 via kcadm (no curl needed), print token only.
TOKINNER='K=/opt/keycloak/bin/kcadm.sh
$K config credentials --server http://localhost:8080/keycloak --realm master --user "$U" --password "$P" >/dev/null 2>&1
# kcadm stores the token in ~/.keycloak/kcadm.config — extract the access token
cat ~/.keycloak/kcadm.config 2>/dev/null | grep -oE "\"token\" : \"[^\"]*\"" | head -1 | sed "s/\"token\" : \"//;s/\"//"'
TOKEN=$(kubectl -n platform-mesh-system exec -i keycloak-0 -- env U="$KCU" P="$KCP" sh -c "$TOKINNER" 2>/dev/null | grep -avi memcache | tr -d "[:space:]")
[ -n "$TOKEN" ] && echo "token minted: len=${#TOKEN}" || { echo "TOKEN MINT FAILED"; exit 1; }

# Now use a throwaway curl pod with ONLY the short-lived token (expires ~60s) to test post.logout.redirect.uris = "+"
KC=http://keycloak-service.platform-mesh-system.svc.cluster.local:8080/keycloak
INNER='set -e
AUTH="Authorization: Bearer $TOKEN"
ID=$(curl -s -H "$AUTH" "$KC/admin/realms/fridaytest/clients?clientId=aitrust-mt-app" | grep -oE "\"id\":\"[^\"]*\"" | head -1 | sed "s/\"id\":\"//;s/\"//")
echo "client id: $ID"
curl -s -H "$AUTH" "$KC/admin/realms/fridaytest/clients/$ID" > /tmp/c.json
# merge attribute = "+" (Keycloak: reuse registered redirect URIs for post-logout) using sed (no jq/python in curl img)
# insert/replace attributes with the post-logout key; if attributes {} present, replace it
sed "s/\"attributes\":{[^}]*}/\"attributes\":{\"post.logout.redirect.uris\":\"+\"}/" /tmp/c.json > /tmp/c2.json
grep -q "post.logout.redirect.uris" /tmp/c2.json || sed "s/}$/,\"attributes\":{\"post.logout.redirect.uris\":\"+\"}}/" /tmp/c.json > /tmp/c2.json
H=$(curl -s -o /tmp/put.out -w "%{http_code}" -X PUT -H "$AUTH" -H "Content-Type: application/json" "$KC/admin/realms/fridaytest/clients/$ID" -d @/tmp/c2.json)
echo "PUT http: $H"; [ "$H" = "204" ] || cat /tmp/put.out
echo "-- verify --"
curl -s -H "$AUTH" "$KC/admin/realms/fridaytest/clients/$ID" | grep -oE "post.logout.redirect.uris\":\"[^\"]*\"" || echo "  attribute NOT set"'
kubectl -n "$NS" run putattr-$$ --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet \
  --env="TOKEN=$TOKEN" --env="KC=$KC" --command -- sh -c "$INNER" 2>&1 | f
echo DONE
