#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
GWNS=platform-mesh-system
REALM=poc2
SECRET="aitrust-mt-users-backend-secret"
KCPOD=$(kubectl -n "$GWNS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep -E '^keycloak-[0-9]' | awk '{print $1}' | head -1)
echo "kc pod: $KCPOD realm: $REALM"
kubectl -n "$GWNS" exec "$KCPOD" -- sh -lc '
set -e
KCADM=/opt/keycloak/bin/kcadm.sh
KA=${KC_BOOTSTRAP_ADMIN_USERNAME:-admin}; KP=${KC_BOOTSTRAP_ADMIN_PASSWORD:-admin}
$KCADM config credentials --server http://localhost:8080/keycloak --realm master --user "$KA" --password "$KP" >/dev/null 2>&1
R='"$REALM"'; SEC='"$SECRET"'
# create or reuse confidential service-account client "users-backend"
CID=$($KCADM get clients -r $R -q clientId=users-backend --fields id 2>/dev/null | grep -oE "[0-9a-f-]{36}" | head -1)
if [ -z "$CID" ]; then
  $KCADM create clients -r $R \
    -s clientId=users-backend -s enabled=true -s protocol=openid-connect \
    -s publicClient=false -s serviceAccountsEnabled=true -s standardFlowEnabled=false \
    -s directAccessGrantsEnabled=false -s "secret=$SEC" >/dev/null
  CID=$($KCADM get clients -r $R -q clientId=users-backend --fields id 2>/dev/null | grep -oE "[0-9a-f-]{36}" | head -1)
  echo "created users-backend client id=$CID"
else
  $KCADM update clients/$CID -r $R -s serviceAccountsEnabled=true -s "secret=$SEC" >/dev/null
  echo "reused users-backend client id=$CID (secret reset)"
fi
# service-account user of this client
SAUSER=$($KCADM get clients/$CID/service-account-user -r $R --fields id 2>/dev/null | grep -oE "[0-9a-f-]{36}" | head -1)
echo "service-account user id=$SAUSER"
# realm-management client id + role ids
RM=$($KCADM get clients -r $R -q clientId=realm-management --fields id 2>/dev/null | grep -oE "[0-9a-f-]{36}" | head -1)
echo "realm-management client id=$RM"
for ROLE in view-users query-users manage-users view-realm manage-realm query-groups; do
  $KCADM add-roles -r $R --uusername service-account-users-backend --cclientid realm-management --rolename $ROLE 2>/dev/null && echo "  granted $ROLE" || echo "  (already/na: $ROLE)"
done
echo "-- resulting service-account roles on realm-management --"
$KCADM get-roles -r $R --uusername service-account-users-backend --cclientid realm-management --effective 2>/dev/null | grep -oE "\"name\"[^,]*" | head -20
' 2>&1 | grep -avi memcache | tail -30
echo DONE
