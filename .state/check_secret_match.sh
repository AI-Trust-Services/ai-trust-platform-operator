#!/bin/bash
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh 2>/dev/null; load_config 2>/dev/null
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
f(){ grep -avi memcache; }

# The proxy reads client-secret from k8s secret aitrust-mt-oauth2-fridaytest. The kc-client Job PUT the
# client with that same value. Compare the FIRST 6 chars of each (don't print full secret).
K8S_SEC=$(kubectl -n "$NS" get secret aitrust-mt-oauth2-fridaytest -o jsonpath='{.data.client-secret}' 2>/dev/null | base64 -d)
echo "k8s client-secret (first 6): ${K8S_SEC:0:6}...  len=${#K8S_SEC}"

KCU=$(kubectl -n "$NS" get secret mesh-keycloak-admin -o jsonpath='{.data.username}' | base64 -d)
KCP=$(kubectl -n "$NS" get secret mesh-keycloak-admin -o jsonpath='{.data.password}' | base64 -d)
INNER='K=/opt/keycloak/bin/kcadm.sh
$K config credentials --server http://localhost:8080/keycloak --realm master --user "$U" --password "$P" >/dev/null 2>&1
CID=$($K get clients -r fridaytest -q clientId=aitrust-mt-app --fields id --format csv --noquotes 2>/dev/null | head -1)
KCSEC=$($K get clients/$CID/client-secret -r fridaytest 2>/dev/null | grep -oE "\"value\" : \"[^\"]*\"" | sed "s/.*: \"//;s/\"//")
echo "keycloak client-secret (first 6): ${KCSEC:0:6}...  len=${#KCSEC}"'
kubectl -n platform-mesh-system exec -i keycloak-0 -- env U="$KCU" P="$KCP" sh -c "$INNER" 2>&1 | f

echo; echo "===== proxy pod: which secret gen is it using? (restart to be safe) ====="
kubectl -n "$NS" get pods -l org=fridaytest -l app=oauth2-proxy-org --no-headers 2>&1 | f
echo DONE
