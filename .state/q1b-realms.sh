#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config >/dev/null 2>&1
export KUBECONFIG="$SHOOT_KUBECONFIG"
GWNS=platform-mesh-system
echo "=== list realms in mesh keycloak via kcadm (inside keycloak-0) ==="
kubectl -n $GWNS exec keycloak-0 -- sh -lc '
  /opt/keycloak/bin/kcadm.sh config credentials --server http://localhost:8080/keycloak --realm master --user "$KC_BOOTSTRAP_ADMIN_USERNAME" --password "$KC_BOOTSTRAP_ADMIN_PASSWORD" >/dev/null 2>&1 && echo "AUTH_OK" || echo "AUTH_FAIL"
  echo "--- realms (realm,displayName,enabled) ---"
  /opt/keycloak/bin/kcadm.sh get realms --fields realm,displayName,enabled 2>&1
' 2>&1 | grep -avi memcache
