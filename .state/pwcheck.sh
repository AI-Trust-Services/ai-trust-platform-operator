#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
echo "=== the ACTUAL admin password in app-secrets ==="
PW=$(kubectl -n "$NS" get secret app-secrets -o jsonpath='{.data.KEYCLOAK_ADMIN_PASSWORD}' 2>/dev/null | base64 -d)
USER=$(kubectl -n "$NS" get secret app-secrets -o jsonpath='{.data.KEYCLOAK_ADMIN}' 2>/dev/null | base64 -d)
echo "secret admin user='$USER' password='$PW'"
KCPOD=$(kubectl -n "$NS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep '^keycloak-[0-9a-f]' | awk '{print $1}' | head -1)
echo "=== does kcadm auth on localhost with the SECRET's creds? (proves whether they match the real admin) ==="
kubectl -n "$NS" exec "$KCPOD" -- sh -lc "/opt/keycloak/bin/kcadm.sh config credentials --server http://localhost:8080/keycloak --realm master --user '$USER' --password '$PW' && /opt/keycloak/bin/kcadm.sh get realms/master --fields realm && echo AUTH_OK_WITH_SECRET_CREDS" 2>&1 | grep -avi memcache | tail -6
echo DONE
