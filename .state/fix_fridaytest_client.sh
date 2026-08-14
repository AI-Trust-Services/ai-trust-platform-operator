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

# kcadm update-clients sets the post.logout.redirect.uris attribute directly. Runs inside keycloak-0 (creds via env, not argv).
INNER='K=/opt/keycloak/bin/kcadm.sh
$K config credentials --server http://localhost:8080/keycloak --realm master --user "$U" --password "$P" >/dev/null 2>&1
CID=$($K get clients -r fridaytest -q clientId=aitrust-mt-app --fields id --format csv --noquotes 2>/dev/null | head -1)
echo "client id: $CID"
$K update clients/$CID -r fridaytest -s "attributes.\"post.logout.redirect.uris\"=$ORIGIN/*" 2>&1
echo "-- verify --"
$K get clients/$CID -r fridaytest --fields clientId,attributes 2>/dev/null'
kubectl -n platform-mesh-system exec -i keycloak-0 -- env U="$KCU" P="$KCP" ORIGIN="$ORIGIN" sh -c "$INNER" 2>&1 | f
echo DONE
