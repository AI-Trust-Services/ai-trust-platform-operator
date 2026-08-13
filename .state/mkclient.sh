#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
GWNS=platform-mesh-system
REALM=poc2
CB="https://ai-trust-mt.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu/oauth2/callback"
ORIGIN="https://ai-trust-mt.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu"
SECRET="aitrust-mt-oauth2-secret"
KCPOD=$(kubectl -n "$GWNS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep -E '^keycloak-[0-9a-f]' | awk '{print $1}' | head -1)
echo "kc pod: $KCPOD  realm: $REALM"
kubectl -n "$GWNS" exec "$KCPOD" -- sh -lc '
KA=${KC_BOOTSTRAP_ADMIN_USERNAME:-admin}; KP=${KC_BOOTSTRAP_ADMIN_PASSWORD:-admin}
/opt/keycloak/bin/kcadm.sh config credentials --server http://localhost:8080/keycloak --realm master --user "$KA" --password "$KP" >/dev/null 2>&1 || { echo AUTH_FAIL; exit 1; }
# does an oauth2-proxy client already exist in '"$REALM"'?
EXIST=$(/opt/keycloak/bin/kcadm.sh get clients -r '"$REALM"' -q clientId=oauth2-proxy --fields id 2>/dev/null | grep -oE "\"id\"[^,]*" | head -1)
if [ -n "$EXIST" ]; then echo "oauth2-proxy client already exists in '"$REALM"'"; else
  /opt/keycloak/bin/kcadm.sh create clients -r '"$REALM"' \
    -s clientId=oauth2-proxy -s enabled=true -s protocol=openid-connect -s publicClient=false \
    -s "secret='"$SECRET"'" -s standardFlowEnabled=true -s directAccessGrantsEnabled=false \
    -s "redirectUris=[\"'"$CB"'\"]" -s "webOrigins=[\"'"$ORIGIN"'\"]" -s fullScopeAllowed=true 2>&1 | tail -2
  echo "created oauth2-proxy client in '"$REALM"' (secret='"$SECRET"')"
fi
' 2>&1 | grep -avi memcache | tail -8
echo DONE
