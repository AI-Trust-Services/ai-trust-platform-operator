#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
NS=aitp-25veqwflh7syq7fm-d
echo "=== dup namespace status ==="
sk get ns aitp-33hins0iklcwfg45-d --ignore-not-found 2>&1 | grep -av memcache | tail -1 || true
echo "(empty/NotFound = fully gone)"
echo "=== good instance keycloak client oauth2-proxy redirectUris ==="
KCP=$(sk -n "$NS" get pods 2>/dev/null | grep -av memcache | grep '^keycloak-' | grep Running | awk '{print $1}' | head -1)
echo "keycloak pod: $KCP"
sk -n "$NS" exec "$KCP" -- bash -c '/opt/keycloak/bin/kcadm.sh config credentials --server http://localhost:8080/keycloak --realm master --user "$KEYCLOAK_ADMIN" --password "$KEYCLOAK_ADMIN_PASSWORD" >/dev/null 2>&1 && /opt/keycloak/bin/kcadm.sh get clients -r ai-trust -q clientId=oauth2-proxy --fields clientId,redirectUris,webOrigins 2>/dev/null' 2>&1 | grep -av memcache | head -12
echo "=== external login flow on the CORRECT host: /oauth2/start should 302 to keycloak ==="
H=25veqwflh7syq7fm-d.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu
sk -n platform-mesh-system run pls-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet -- \
  curl -sk -o /dev/null -w '/oauth2/start: http=%{http_code} -> %{redirect_url}\n' "https://$H/oauth2/start" 2>&1 | grep -av memcache
