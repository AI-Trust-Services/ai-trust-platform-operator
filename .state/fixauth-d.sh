#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
NS=aitp-33hins0iklcwfg45-d
URL=https://d.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu
echo "=== patch oauth2-proxy args to the /keycloak-prefixed URLs + cookie-secure=true ==="
sk -n "$NS" patch deploy oauth2-proxy --type=json -p '[{"op":"replace","path":"/spec/template/spec/containers/0/args","value":[
"--provider=oidc",
"--client-id=oauth2-proxy",
"--client-secret=$(KEYCLOAK_CLIENT_SECRET)",
"--oidc-issuer-url=http://keycloak:8080/keycloak/realms/ai-trust",
"--login-url='"$URL"'/keycloak/realms/ai-trust/protocol/openid-connect/auth",
"--redeem-url=http://keycloak:8080/keycloak/realms/ai-trust/protocol/openid-connect/token",
"--oidc-jwks-url=http://keycloak:8080/keycloak/realms/ai-trust/protocol/openid-connect/certs",
"--skip-oidc-discovery=true",
"--insecure-oidc-skip-issuer-verification=true",
"--redirect-url='"$URL"'/oauth2/callback",
"--upstream=http://shell:80",
"--http-address=0.0.0.0:4180",
"--cookie-secret=$(OAUTH2_PROXY_COOKIE_SECRET)",
"--cookie-secure=true",
"--email-domain=*",
"--pass-authorization-header=true",
"--backend-logout-url=http://keycloak:8080/keycloak/realms/ai-trust/protocol/openid-connect/logout"
]}]' 2>&1 | grep -av memcache
echo "=== fix keycloak readiness path to /keycloak/realms/master ==="
sk -n "$NS" patch deploy keycloak --type=json -p '[{"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/httpGet/path","value":"/keycloak/realms/master"}]' 2>&1 | grep -av memcache
echo "=== wait for oauth2-proxy rollout ==="
sk -n "$NS" rollout status deploy/oauth2-proxy --timeout=120s 2>&1 | grep -av memcache | tail -1
echo "=== verify the new args ==="
sk -n "$NS" get deploy oauth2-proxy -o jsonpath='{range .spec.template.spec.containers[0].args[*]}{@}{"\n"}{end}' 2>&1 | grep -av memcache | grep -iE 'issuer|login|redeem|jwks|cookie-secure'
