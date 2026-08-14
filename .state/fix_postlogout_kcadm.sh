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

# Use kcadm INSIDE keycloak-0 with the JSON-array attribute syntax kcadm supports:
#   -s 'attributes.post.logout.redirect.uris=...'  breaks on the dots, so use the -f file / raw form.
# kcadm accepts multivalued attribute via: -s "attributes.\"post.logout.redirect.uris\"=[\"a\",\"b\"]" ? No.
# Reliable: write a partial JSON to a temp file in the pod and PUT via kcadm update -f.
INNER='K=/opt/keycloak/bin/kcadm.sh
$K config credentials --server http://localhost:8080/keycloak --realm master --user "$U" --password "$P" >/dev/null 2>&1
CID=$($K get clients -r fridaytest -q clientId=aitrust-mt-app --fields id --format csv --noquotes 2>/dev/null | head -1)
echo "client id: $CID"
# partial update file: only the attributes we want to merge
printf "%s" "{\"attributes\":{\"post.logout.redirect.uris\":\"$ORIGIN##$ORIGIN/*\"}}" > /tmp/upd.json
echo "-- update file --"; cat /tmp/upd.json; echo
$K update clients/$CID -r fridaytest -f /tmp/upd.json 2>&1 && echo "  kcadm update OK"
echo "-- verify via kcadm get (raw) --"
$K get clients/$CID -r fridaytest 2>/dev/null | grep -A3 attributes | head -6'
kubectl -n platform-mesh-system exec -i keycloak-0 -- env U="$KCU" P="$KCP" ORIGIN="$ORIGIN" sh -c "$INNER" 2>&1 | f
echo DONE
