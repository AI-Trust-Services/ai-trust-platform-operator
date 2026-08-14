#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp; GWNS=platform-mesh-system; LB=130.214.18.166
PH=ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu

echo "=== is the shoot kubeconfig valid? ==="
kubectl -n "$NS" get ns >/dev/null 2>&1 && echo "  ok" || { echo "  KUBECONFIG_EXPIRED — need login.sh"; exit 7; }

echo "=== does the 'berlin' realm exist in the mesh Keycloak? ==="
KCPOD=$(kubectl -n "$GWNS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep -E '^keycloak-[0-9]' | awk '{print $1}' | head -1)
kubectl -n "$GWNS" exec "$KCPOD" -- sh -lc '
KA=${KC_BOOTSTRAP_ADMIN_USERNAME:-admin}; KP=${KC_BOOTSTRAP_ADMIN_PASSWORD:-admin}
/opt/keycloak/bin/kcadm.sh config credentials --server http://localhost:8080/keycloak --realm master --user "$KA" --password "$KP" >/dev/null 2>&1
echo "-- realm berlin present? --"; /opt/keycloak/bin/kcadm.sh get realms/berlin --fields realm 2>&1 | head -3
echo "-- aitrust-mt-app client in berlin? --"; /opt/keycloak/bin/kcadm.sh get clients -r berlin -q clientId=aitrust-mt-app --fields clientId,enabled 2>&1 | head -5
echo "-- users in berlin --"; /opt/keycloak/bin/kcadm.sh get users -r berlin --fields username 2>/dev/null | grep -i username | head
' 2>&1 | grep -avi memcache | head -20

echo "=== public auth endpoint for berlin realm (200 = realm serves; 404 = no realm) ==="
kubectl -n "$NS" run b-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet --command -- \
  sh -c "curl -sk -o /dev/null -w 'berlin auth: http=%{http_code}\n' --resolve $PH:443:$LB 'https://$PH/keycloak/realms/berlin/protocol/openid-connect/auth?client_id=aitrust-mt-app&response_type=code&scope=openid&redirect_uri=https://x'" 2>&1 | grep -avi memcache | grep http=

echo "=== is there a berlin Subscription + per-org proxy/route? ==="
kubectl get subscriptions.sub.aitrustmt.msp -A -o jsonpath='{range .items[*]}{.metadata.name}={.spec.org}/{.status.phase}{"\n"}{end}' 2>&1 | grep -avi memcache | grep -i berlin || echo "  no berlin subscription"
kubectl -n "$NS" get deploy,svc -l org=berlin --no-headers 2>&1 | grep -avi memcache || echo "  no berlin per-org resources"
kubectl -n platform-mesh-system get httproute aitrust-mt-berlin --no-headers 2>&1 | grep -avi memcache || echo "  no berlin httproute"
echo DONE
