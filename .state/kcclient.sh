#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
NS=aitp-33hins0iklcwfg45-d
echo "=== oauth2-proxy pod: which replicaset/args are ACTUALLY live + recent logs ==="
sk -n "$NS" get pods -l app.kubernetes.io/name=oauth2-proxy -o name 2>&1 | grep -av memcache | head
POD=$(sk -n "$NS" get pods 2>/dev/null | grep -av memcache | grep oauth2-proxy | grep Running | awk '{print $1}' | head -1)
echo "live pod: $POD"
sk -n "$NS" logs "$POD" --tail=30 2>&1 | grep -av memcache | grep -ivE 'GET /ping|/ready' | tail -20
echo ""
echo "=== Keycloak: the oauth2-proxy client redirectUris (via kcadm inside the keycloak pod) ==="
KCP=$(sk -n "$NS" get pods 2>/dev/null | grep -av memcache | grep '^keycloak-' | grep Running | awk '{print $1}' | head -1)
echo "keycloak pod: $KCP"
sk -n "$NS" exec "$KCP" -- bash -c '
/opt/keycloak/bin/kcadm.sh config credentials --server http://localhost:8080/keycloak --realm master --user "$KEYCLOAK_ADMIN" --password "$KEYCLOAK_ADMIN_PASSWORD" >/dev/null 2>&1 && \
/opt/keycloak/bin/kcadm.sh get clients -r ai-trust -q clientId=oauth2-proxy --fields clientId,redirectUris,webOrigins,enabled 2>/dev/null
' 2>&1 | grep -av memcache | head -20
