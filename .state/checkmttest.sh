#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
GWNS=platform-mesh-system; LB=130.214.18.166
PH=ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu
echo "=== is the mttest realm's auth endpoint live (public)? ==="
kubectl -n "$GWNS" run r-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet --command -- \
  sh -c "curl -sk -o /dev/null -w 'mttest auth: http=%{http_code}\n' --resolve $PH:443:$LB 'https://$PH/keycloak/realms/mttest/protocol/openid-connect/auth?client_id=x&response_type=code&scope=openid&redirect_uri=https://x'" 2>&1 | grep -avi memcache | grep http=
echo "=== users in the mttest realm (so login will actually work) ==="
KCPOD=$(kubectl -n "$GWNS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep -E '^keycloak-[0-9]' | awk '{print $1}' | head -1)
kubectl -n "$GWNS" exec "$KCPOD" -- sh -lc '
KA=${KC_BOOTSTRAP_ADMIN_USERNAME:-admin}; KP=${KC_BOOTSTRAP_ADMIN_PASSWORD:-admin}
/opt/keycloak/bin/kcadm.sh config credentials --server http://localhost:8080/keycloak --realm master --user "$KA" --password "$KP" >/dev/null 2>&1
echo "-- mttest users --"; /opt/keycloak/bin/kcadm.sh get users -r mttest --fields username,email 2>/dev/null
' 2>&1 | grep -avi memcache | grep -iE 'username|email|--' | head -20
echo DONE
