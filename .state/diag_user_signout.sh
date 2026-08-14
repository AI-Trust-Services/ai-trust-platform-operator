#!/bin/bash
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh 2>/dev/null; load_config 2>/dev/null
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
f(){ grep -avi memcache; }

# 1) Does the new user exist in Keycloak realm fridaytest? (auth side)
KCU=$(kubectl -n "$NS" get secret mesh-keycloak-admin -o jsonpath='{.data.username}' | base64 -d)
KCP=$(kubectl -n "$NS" get secret mesh-keycloak-admin -o jsonpath='{.data.password}' | base64 -d)
INNER='K=/opt/keycloak/bin/kcadm.sh
$K config credentials --server http://localhost:8080/keycloak --realm master --user "$U" --password "$P" >/dev/null 2>&1
echo "=== realm fridaytest users (auth side — who can LOG IN) ==="
$K get users -r fridaytest --fields username,email,enabled 2>/dev/null'
echo "----- KEYCLOAK (authentication) -----"
kubectl -n platform-mesh-system exec -i keycloak-0 -- env U="$KCU" P="$KCP" sh -c "$INNER" 2>&1 | f

# 2) sign-out config on the fridaytest oauth2-proxy
echo; echo "----- oauth2-proxy-fridaytest logout wiring -----"
kubectl -n "$NS" get deploy oauth2-proxy-fridaytest -o jsonpath='{range .spec.template.spec.containers[0].args[*]}{@}{"\n"}{end}' 2>&1 | f | grep -iE 'logout|sign_?out|cookie|whitelist|redirect'
echo DONE
