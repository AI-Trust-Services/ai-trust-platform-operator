#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
KCPOD=$(kubectl -n "$NS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep '^keycloak-[0-9a-f]' | awk '{print $1}' | head -1)
echo "kc pod: $KCPOD"
echo "=== set master realm sslRequired=NONE (allow in-cluster HTTP admin auth) via kcadm on localhost ==="
kubectl -n "$NS" exec "$KCPOD" -- sh -lc '
  /opt/keycloak/bin/kcadm.sh config credentials --server http://localhost:8080/keycloak --realm master --user "$KEYCLOAK_ADMIN" --password "$KEYCLOAK_ADMIN_PASSWORD" >/tmp/l 2>&1 || { echo LOGIN_FAIL; cat /tmp/l; exit 1; }
  /opt/keycloak/bin/kcadm.sh update realms/master -s sslRequired=NONE 2>&1 | tail -3
  echo "master sslRequired now: $(/opt/keycloak/bin/kcadm.sh get realms/master --fields sslRequired 2>/dev/null)"
' 2>&1 | grep -avi memcache | tail -10
echo "=== re-probe token via svc dns (expect 200 now) ==="
kubectl -n "$NS" run tv-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet --command -- \
  sh -c 'curl -s -o /dev/null -w "svc-dns token: http=%{http_code}\n" -d "client_id=admin-cli&username=admin&password=admin&grant_type=password" http://keycloak.aitrust-mt-msp.svc.cluster.local:8080/keycloak/realms/master/protocol/openid-connect/token' 2>&1 | grep -avi memcache | grep http=
echo DONE
