#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
echo "KUBECONFIG=$KUBECONFIG"
echo "current-context: $(kubectl config current-context 2>&1 | grep -avi memcache)"
echo "== deploys in $NS =="
kubectl -n "$NS" get deploy 2>/dev/null | grep -avi memcache | grep -iE 'users|registry|shell|oauth'
echo "== users-backend deploy exists? =="
kubectl -n "$NS" get deploy users-backend --no-headers 2>&1 | grep -avi memcache
echo "== users-backend code: keycloak admin usage =="
kubectl -n "$NS" exec deploy/users-backend -- sh -lc 'grep -rnE "realm-management|manage-users|view-users|query-users|client_credentials|admin/realms|KEYCLOAK_REALM|CLIENT_SECRET" /app 2>/dev/null | grep -viE "[.]pyc|/tests?/" | head -25' 2>&1 | grep -avi memcache | head -25
echo DONE
