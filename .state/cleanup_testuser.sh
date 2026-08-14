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
TID=$($K get users -r fridaytest -q username=e2e-tenant-check@example.com --fields id --format csv --noquotes 2>/dev/null | head -1)
if [ -n "$TID" ]; then $K delete users/$TID -r fridaytest 2>&1 && echo "cleaned up test user $TID"; else echo "test user already gone"; fi'
kubectl -n platform-mesh-system exec -i keycloak-0 -- env U="$KCU" P="$KCP" sh -c "$INNER" 2>&1 | f
echo DONE
