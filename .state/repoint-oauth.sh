#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp; GWNS=platform-mesh-system
REALM=poc2
SECRET="aitrust-mt-oauth2-secret"
COOKIE="$(kubectl -n "$NS" get secret app-secrets -o jsonpath='{.data.OAUTH2_PROXY_COOKIE_SECRET}' | base64 -d)"
# in-cluster mesh keycloak (token/jwks/redeem) and PUBLIC mesh keycloak (browser login)
KC_INT="http://keycloak-service.$GWNS.svc.cluster.local:8080/keycloak/realms/$REALM"
KC_PUB="https://ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu/keycloak/realms/$REALM"
APP="https://ai-trust-mt.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu"

echo "=== repoint shared-app oauth2-proxy at the MESH poc2 realm ==="
ARGS="[\"--provider=oidc\",\"--client-id=oauth2-proxy\",\"--client-secret=$SECRET\",\"--oidc-issuer-url=$KC_INT\",\"--login-url=$KC_PUB/protocol/openid-connect/auth\",\"--redeem-url=$KC_INT/protocol/openid-connect/token\",\"--oidc-jwks-url=$KC_INT/protocol/openid-connect/certs\",\"--skip-oidc-discovery=true\",\"--insecure-oidc-skip-issuer-verification=true\",\"--insecure-oidc-allow-unverified-email=true\",\"--redirect-url=$APP/oauth2/callback\",\"--upstream=http://shell:80\",\"--http-address=0.0.0.0:4180\",\"--reverse-proxy=true\",\"--cookie-secret=$COOKIE\",\"--cookie-secure=true\",\"--email-domain=*\",\"--pass-authorization-header=true\",\"--backend-logout-url=$KC_PUB/protocol/openid-connect/logout\"]"
kubectl -n "$NS" patch deploy oauth2-proxy --type=json -p "[{\"op\":\"replace\",\"path\":\"/spec/template/spec/containers/0/args\",\"value\":$ARGS}]" 2>&1 | grep -avi memcache
# it also references KEYCLOAK_CLIENT_SECRET/KEYCLOAK_PUBLIC_URL via env $(...) — we hardcoded literals in args, so env not needed, but clear the $(VAR) confusion is avoided since we replaced the whole args array.
kubectl -n "$NS" rollout status deploy/oauth2-proxy --timeout=120s 2>&1 | grep -avi memcache | tail -1
echo "=== verify: the auth endpoint on the shared host now resolves the poc2 realm (no 'Realm does not exist') ==="
LB=130.214.18.166; H=ai-trust-mt.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu
kubectl -n "$NS" run v-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet --command -- \
  sh -c "curl -sk -o /dev/null -w 'app / (should 302 to mesh login): http=%{http_code} -> %{redirect_url}\n' --resolve $H:443:$LB https://$H/" 2>&1 | grep -avi memcache | grep http=
echo "-- the mesh poc2 auth endpoint itself (public) --"
PH=ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu
kubectl -n "$NS" run p-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet --command -- \
  sh -c "curl -sk -o /dev/null -w 'poc2 auth endpoint: http=%{http_code}\n' --resolve $PH:443:$LB 'https://$PH/keycloak/realms/poc2/protocol/openid-connect/auth?client_id=oauth2-proxy&response_type=code&redirect_uri=$APP/oauth2/callback&scope=openid'" 2>&1 | grep -avi memcache | grep http=
echo DONE
