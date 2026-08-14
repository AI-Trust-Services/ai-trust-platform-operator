#!/bin/bash
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh 2>/dev/null; load_config 2>/dev/null
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
f(){ grep -avi memcache; }

# Full login+logout reproduction via a curl pod (cookie jar), against the fridaytest proxy + keycloak, in-cluster.
PROXY=http://oauth2-proxy-fridaytest.aitrust-mt-msp.svc.cluster.local:8080
KC=http://keycloak-service.platform-mesh-system.svc.cluster.local:8080/keycloak
ORIGIN=https://ai-trust-mt-fridaytest.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu

INNER='set -e
CJ=/tmp/cj.txt
echo "=== 1) GET /oauth2/start -> keycloak auth URL ==="
AUTHURL=$(curl -s -c $CJ -o /dev/null -w "%{redirect_url}" "$PROXY/oauth2/start" )
echo "auth url: $AUTHURL" | head -c 200; echo
echo "=== 2) GET the keycloak login page (follow to get the form action + session cookies) ==="
# rewrite public host in AUTHURL to in-cluster KC so we can reach it
KCAUTH=$(echo "$AUTHURL" | sed "s#https://ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu/keycloak#$KC#")
LOGINPAGE=$(curl -s -c $CJ -b $CJ "$KCAUTH")
FORMACTION=$(echo "$LOGINPAGE" | grep -oE "action=\"[^\"]*\"" | head -1 | sed "s/action=\"//;s/\"//" | sed "s/\&amp;/\&/g")
echo "form action (first 160): ${FORMACTION:0:160}"
[ -z "$FORMACTION" ] && { echo "NO LOGIN FORM — dumping first 400 chars:"; echo "$LOGINPAGE" | head -c 400; exit 1; }
# the form action points at the PUBLIC host; rewrite to in-cluster
FA=$(echo "$FORMACTION" | sed "s#https://ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu/keycloak#$KC#")
echo "=== 3) POST credentials ==="
for USER in mircea.craciun@sap.com mircea.craciun@saap.com; do
  echo "-- trying $USER --"
  CODE=$(curl -s -c $CJ -b $CJ -o /dev/null -w "%{http_code}:%{redirect_url}" --data-urlencode "username=$USER" --data-urlencode "password=password1" "$FA" || true)
  echo "   login POST result: $CODE" | head -c 300; echo
  echo "$CODE" | grep -q "oauth2/callback" && { echo "   -> got callback for $USER"; break; }
done
echo "DONE-LOGIN-PHASE"'
kubectl -n "$NS" run loginrepro-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet \
  --env="PROXY=$PROXY" --env="KC=$KC" --env="ORIGIN=$ORIGIN" --command -- sh -c "$INNER" 2>&1 | f
echo DONE
