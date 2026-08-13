#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config >/dev/null 2>&1
export KUBECONFIG="$SHOOT_KUBECONFIG"
GWNS=platform-mesh-system
echo "=== rebac-authz-webhook: exists? image/args ==="
kubectl -n $GWNS get deploy 2>&1 | grep -avi memcache | grep -iE 'rebac|authz|webhook' | head
kubectl -n $GWNS get deploy rebac-authz-webhook -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}ARGS:{.spec.template.spec.containers[0].args}{"\n"}' 2>&1 | grep -avi memcache
echo "--- rebac env (openfga endpoint?) ---"
kubectl -n $GWNS get deploy rebac-authz-webhook -o jsonpath='{range .spec.template.spec.containers[0].env[*]}{.name}={.value}{"\n"}{end}' 2>&1 | grep -avi memcache | head -20
echo
echo "=== iam-service: what does it create? recent logs (realm/role creation) ==="
kubectl -n $GWNS logs deploy/iam-service --tail=60 2>&1 | grep -avi memcache | grep -iE 'realm|role|keycloak|account|create|store|reconcil|error' | head -40
echo
echo "=== account-operator: recent logs (keycloak/realm/store) ==="
kubectl -n $GWNS logs deploy/account-operator --tail=80 2>&1 | grep -avi memcache | grep -iE 'realm|keycloak|store|fga|created|reconcil' | head -30
