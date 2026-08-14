#!/bin/bash
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh 2>/dev/null; load_config 2>/dev/null
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
f(){ grep -avi memcache; }

KCU=$(kubectl -n "$NS" get secret mesh-keycloak-admin -o jsonpath='{.data.username}' | base64 -d)
KCP=$(kubectl -n "$NS" get secret mesh-keycloak-admin -o jsonpath='{.data.password}' | base64 -d)
ORIGIN="https://ai-trust-mt-fridaytest.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu"

# Raw Admin REST: token, get client id, GET full rep, merge attribute via python3 (present in keycloak img? use sed if not), PUT back.
INNER='set -e
KC=http://localhost:8080/keycloak
TOK=$(curl -s --fail "$KC/realms/master/protocol/openid-connect/token" -d grant_type=password -d client_id=admin-cli -d "username=$U" -d "password=$P" | sed -n "s/.*\"access_token\":\"\([^\"]*\)\".*/\1/p")
AUTH="Authorization: Bearer $TOK"
ID=$(curl -s -H "$AUTH" "$KC/admin/realms/fridaytest/clients?clientId=aitrust-mt-app" | grep -oE "\"id\":\"[^\"]*\"" | head -1 | sed "s/\"id\":\"//;s/\"//")
echo "client id: $ID"
# GET full representation
curl -s -H "$AUTH" "$KC/admin/realms/fridaytest/clients/$ID" > /tmp/c.json
# inject attributes via python3 (keycloak 25 image ships python3? try; fallback jq; fallback sed)
if command -v python3 >/dev/null 2>&1; then
  python3 - "$ORIGIN" <<PY
import json,sys
o=json.load(open("/tmp/c.json"))
o.setdefault("attributes",{})["post.logout.redirect.uris"]=sys.argv[1]+"/*"
json.dump(o,open("/tmp/c2.json","w"))
print("merged via python3")
PY
else
  echo "no python3 — using jq"; jq --arg u "$ORIGIN/*" ".attributes[\"post.logout.redirect.uris\"]=\$u" /tmp/c.json > /tmp/c2.json
fi
HTTP=$(curl -s -o /tmp/put.out -w "%{http_code}" -X PUT -H "$AUTH" -H "Content-Type: application/json" "$KC/admin/realms/fridaytest/clients/$ID" -d @/tmp/c2.json)
echo "PUT http: $HTTP"; [ "$HTTP" = "204" ] || cat /tmp/put.out
echo "-- verify attributes --"
curl -s -H "$AUTH" "$KC/admin/realms/fridaytest/clients/$ID" | grep -oE "\"post.logout.redirect.uris\":\"[^\"]*\"" || echo "  (attribute still not set)"'
kubectl -n platform-mesh-system exec -i keycloak-0 -- env U="$KCU" P="$KCP" ORIGIN="$ORIGIN" sh -c "$INNER" 2>&1 | f
echo DONE
