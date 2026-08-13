#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
KCPOD=$(kubectl -n "$NS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep '^keycloak-[0-9a-f]' | awk '{print $1}' | head -1)
echo "kc pod: $KCPOD"
echo "=== does admin auth ACTUALLY work? kcadm get realms (only succeeds if authenticated) ==="
kubectl -n "$NS" exec "$KCPOD" -- sh -lc '
  /opt/keycloak/bin/kcadm.sh config credentials --server http://localhost:8080/keycloak --realm master --user "$KEYCLOAK_ADMIN" --password "$KEYCLOAK_ADMIN_PASSWORD" >/tmp/l 2>&1
  /opt/keycloak/bin/kcadm.sh get realms --fields realm 2>&1 | head -20
' 2>&1 | grep -avi memcache | tail -20
echo "=== KC first-boot admin line (grep whole log) ==="
kubectl -n "$NS" logs "$KCPOD" 2>&1 | grep -avi memcache | grep -iE "admin user|Created temporary|bootstrap|KEYCLOAK_ADMIN|added user|initializing admin" | tail -8
echo DONE
