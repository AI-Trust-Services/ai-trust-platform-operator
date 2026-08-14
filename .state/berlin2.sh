#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config
rm -f "$SHOOT_KUBECONFIG"; mint_shoot_kubeconfig 2>&1 | grep -avi memcache | tail -1
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp; GWNS=platform-mesh-system; LB=130.214.18.166
PH=ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu
KCPOD=$(kubectl -n "$GWNS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep -E '^keycloak-[0-9]' | awk '{print $1}' | head -1)
echo "=== berlin realm + client + users ==="
kubectl -n "$GWNS" exec "$KCPOD" -- sh -lc '
KA=${KC_BOOTSTRAP_ADMIN_USERNAME:-admin}; KP=${KC_BOOTSTRAP_ADMIN_PASSWORD:-admin}
/opt/keycloak/bin/kcadm.sh config credentials --server http://localhost:8080/keycloak --realm master --user "$KA" --password "$KP" >/dev/null 2>&1
echo "-- realm berlin? --"; /opt/keycloak/bin/kcadm.sh get realms/berlin --fields realm,enabled 2>&1 | head -4
echo "-- aitrust-mt-app client in berlin (id, redirectUris)? --"; /opt/keycloak/bin/kcadm.sh get clients -r berlin -q clientId=aitrust-mt-app --fields clientId,enabled,redirectUris 2>&1 | head -12
echo "-- users in berlin --"; /opt/keycloak/bin/kcadm.sh get users -r berlin --fields username,email,enabled 2>&1 | grep -iE "username|email|enabled" | head -20
' 2>&1 | grep -avi memcache | head -30
echo "=== berlin subscription + per-org resources ==="
kubectl get subscriptions.sub.aitrustmt.msp -A -o jsonpath='{range .items[*]}{.metadata.name}={.spec.org}/{.status.phase}{"\n"}{end}' 2>&1 | grep -avi memcache | grep -i berlin || echo "  none"
kubectl -n "$NS" get deploy -l org=berlin --no-headers 2>&1 | grep -avi memcache || echo "  no berlin proxy"
echo DONE
