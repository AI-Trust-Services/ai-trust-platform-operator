#!/bin/bash
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh 2>/dev/null; load_config 2>/dev/null
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
f(){ grep -avi memcache; }
SUFFIX="ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu"

KCU=$(kubectl -n "$NS" get secret mesh-keycloak-admin -o jsonpath='{.data.username}' | base64 -d)
KCP=$(kubectl -n "$NS" get secret mesh-keycloak-admin -o jsonpath='{.data.password}' | base64 -d)

# Loop the remaining tenants inside keycloak-0 (creds via env, not argv).
INNER='K=/opt/keycloak/bin/kcadm.sh
$K config credentials --server http://localhost:8080/keycloak --realm master --user "$U" --password "$P" >/dev/null 2>&1
for ORG in livedemo mirceatest mttest2 sohan; do
  ORIGIN="https://ai-trust-mt-$ORG.$SUFFIX"
  CID=$($K get clients -r $ORG -q clientId=aitrust-mt-app --fields id --format csv --noquotes 2>/dev/null | head -1)
  if [ -z "$CID" ]; then echo "  $ORG: no client (skip)"; continue; fi
  printf "%s" "{\"attributes\":{\"post.logout.redirect.uris\":\"$ORIGIN##$ORIGIN/*\"}}" > /tmp/upd.json
  $K update clients/$CID -r $ORG -f /tmp/upd.json 2>&1 && echo "  $ORG: updated"
done
echo "-- verify all --"
for ORG in fridaytest livedemo mirceatest mttest2 sohan; do
  CID=$($K get clients -r $ORG -q clientId=aitrust-mt-app --fields id --format csv --noquotes 2>/dev/null | head -1)
  V=$($K get clients/$CID -r $ORG 2>/dev/null | grep -oE "post.logout.redirect.uris\" : \"[^\"]*\"" | head -1)
  echo "  $ORG: $V"
done'
kubectl -n platform-mesh-system exec -i keycloak-0 -- env U="$KCU" P="$KCP" SUFFIX="$SUFFIX" sh -c "$INNER" 2>&1 | f
echo DONE
