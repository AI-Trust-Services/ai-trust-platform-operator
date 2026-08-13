#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp; LB=130.214.18.166
H=ai-trust-mt.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu
echo "=== A) what the auth URL returns (the actual error) ==="
kubectl -n "$NS" run a-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet --command -- \
  sh -c "curl -sk --resolve $H:443:$LB 'https://$H/keycloak/realms/ai-trust/protocol/openid-connect/auth?client_id=oauth2-proxy&redirect_uri=https%3A%2F%2F$H%2Foauth2%2Fcallback&response_type=code&scope=openid' -w '\nHTTP=%{http_code}\n' | tail -8" 2>&1 | grep -avi memcache | tail -10
echo "=== B) oauth2-proxy args (what issuer/realm is it using?) ==="
kubectl -n "$NS" get deploy oauth2-proxy -o jsonpath='{range .spec.template.spec.containers[0].args[*]}{@}{"\n"}{end}' 2>&1 | grep -avi memcache | grep -iE 'issuer|login-url|redeem|jwks|realms|keycloak'
echo "=== C) does the shared app run its OWN keycloak, and does it have an 'ai-trust' realm? ==="
kubectl -n "$NS" get deploy keycloak 2>&1 | grep -avi memcache | head -2
KCPOD=$(kubectl -n "$NS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep '^keycloak-[0-9a-f]' | awk '{print $1}' | head -1)
echo "kc pod: $KCPOD"
[ -n "$KCPOD" ] && kubectl -n "$NS" exec "$KCPOD" -- sh -lc '/opt/keycloak/bin/kcadm.sh config credentials --server http://localhost:8080/keycloak --realm master --user "$KEYCLOAK_ADMIN" --password "$KEYCLOAK_ADMIN_PASSWORD" >/dev/null 2>&1 && /opt/keycloak/bin/kcadm.sh get realms --fields realm 2>/dev/null' 2>&1 | grep -avi memcache | grep realm | head
echo "=== D) does /keycloak on the shared host route anywhere? (200/302 vs 404/503) ==="
kubectl -n "$NS" run k-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet --command -- \
  sh -c "curl -sk -o /dev/null -w 'GET /keycloak/realms/ai-trust: http=%{http_code}\n' --resolve $H:443:$LB https://$H/keycloak/realms/ai-trust" 2>&1 | grep -avi memcache | grep http=
echo DONE
