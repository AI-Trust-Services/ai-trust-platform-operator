#!/bin/bash
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh 2>/dev/null; load_config 2>/dev/null
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
f(){ grep -avi memcache; }

echo "===== full kc-client-fridaytest Job log + pod status ====="
kubectl -n "$NS" get pods -l job-name=kc-client-fridaytest --no-headers 2>&1 | f
kubectl -n "$NS" logs job/kc-client-fridaytest --tail=40 2>&1 | f

echo; echo "===== how many aitrust-mt-app clients exist in fridaytest? (dup check) ====="
KCU=$(kubectl -n "$NS" get secret mesh-keycloak-admin -o jsonpath='{.data.username}' | base64 -d)
KCP=$(kubectl -n "$NS" get secret mesh-keycloak-admin -o jsonpath='{.data.password}' | base64 -d)
INNER='K=/opt/keycloak/bin/kcadm.sh
$K config credentials --server http://localhost:8080/keycloak --realm master --user "$U" --password "$P" >/dev/null 2>&1
echo "-- all clients with clientId=aitrust-mt-app in fridaytest --"
$K get clients -r fridaytest -q clientId=aitrust-mt-app --fields id,clientId 2>/dev/null'
kubectl -n platform-mesh-system exec -i keycloak-0 -- env U="$KCU" P="$KCP" sh -c "$INNER" 2>&1 | f
echo DONE
