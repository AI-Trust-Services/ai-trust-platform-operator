#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config >/dev/null 2>&1
export KUBECONFIG="$SHOOT_KUBECONFIG"
GWNS=platform-mesh-system
echo "=== WorkspaceAuthenticationConfiguration CRs (cross-check realm names) ==="
kubectl get crd 2>&1 | grep -avi memcache | grep -iE 'workspaceauth|authenticationconfig' | head
echo "--- instances (any ns / cluster) ---"
kubectl get workspaceauthenticationconfigurations -A 2>&1 | grep -avi memcache | head -30
echo
echo "=== inspect aitrustmt realm: clients + realm roles ==="
kubectl -n $GWNS exec keycloak-0 -- sh -lc '
  /opt/keycloak/bin/kcadm.sh config credentials --server http://localhost:8080/keycloak --realm master --user "$KC_BOOTSTRAP_ADMIN_USERNAME" --password "$KC_BOOTSTRAP_ADMIN_PASSWORD" >/dev/null 2>&1
  echo "--- clients in aitrustmt (clientId) ---"
  /opt/keycloak/bin/kcadm.sh get clients -r aitrustmt --fields clientId,enabled,redirectUris,publicClient 2>&1
  echo "--- realm roles in aitrustmt ---"
  /opt/keycloak/bin/kcadm.sh get roles -r aitrustmt --fields name,description 2>&1
  echo "--- groups in aitrustmt ---"
  /opt/keycloak/bin/kcadm.sh get groups -r aitrustmt --fields name 2>&1
' 2>&1 | grep -avi memcache
