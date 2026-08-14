#!/bin/bash
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh 2>/dev/null; load_config 2>/dev/null
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
f(){ grep -avi memcache; }

KCU=$(kubectl -n "$NS" get secret mesh-keycloak-admin -o jsonpath='{.data.username}' | base64 -d)
KCP=$(kubectl -n "$NS" get secret mesh-keycloak-admin -o jsonpath='{.data.password}' | base64 -d)
INNER='K=/opt/keycloak/bin/kcadm.sh
$K config credentials --server http://localhost:8080/keycloak --realm master --user "$U" --password "$P" >/dev/null 2>&1
UID2=$($K get users -r fridaytest -q username=mircea.craciun@proton.me --fields id --format csv --noquotes 2>/dev/null | head -1)
echo "user id: $UID2"
echo "=== clear UPDATE_PASSWORD required action ==="
$K update users/$UID2 -r fridaytest -s "requiredActions=[]" 2>&1 && echo "  cleared required actions"
echo "=== set a PERMANENT password (temporary=false) ==="
$K set-password -r fridaytest --username mircea.craciun@proton.me --new-password password 2>&1 && echo "  password set (permanent)"
echo "=== verify ==="
$K get users/$UID2 -r fridaytest --fields username,requiredActions,enabled 2>/dev/null'
kubectl -n platform-mesh-system exec -i keycloak-0 -- env U="$KCU" P="$KCP" sh -c "$INNER" 2>&1 | f
echo DONE
