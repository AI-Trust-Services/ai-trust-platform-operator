#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config >/dev/null 2>&1
export KUBECONFIG="$SHOOT_KUBECONFIG"
GWNS=platform-mesh-system
echo "=== who owns the Store CR reconcile? search deploy names for store/fga controllers ==="
kubectl -n $GWNS get deploy 2>&1 | grep -avi memcache | grep -iE 'store|fga|iam|account|extension|rebac|security|kubernetes-graphql' | head
echo
echo "=== keycloak-operator: does it own realm creation? KeycloakRealmImport CRs? ==="
kubectl get crd 2>&1 | grep -avi memcache | grep -iE 'keycloak|realm' | head
echo "--- KeycloakRealmImport instances (per org realm)? ---"
kubectl get keycloakrealmimports.k8s.keycloak.org -A 2>&1 | grep -avi memcache | head -20
kubectl get keycloakrealms -A 2>&1 | grep -avi memcache | head
echo
echo "=== account-operator: subroutine that creates realm? check its logs for keycloak realm ==="
kubectl -n $GWNS logs deploy/account-operator --since=48h 2>&1 | grep -avi memcache | grep -iaE 'realm|keycloak' | head -15
echo
echo "=== iam-service: is it the store reconciler + keycloak realm manager? logs for aitrustmt ==="
kubectl -n $GWNS logs deploy/iam-service --since=48h 2>&1 | grep -avi memcache | grep -iaE 'aitrustmt|realm|store creat|created store|authorization model' | head -15
