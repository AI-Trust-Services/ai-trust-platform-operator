#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
NS=aitp-25veqwflh7syq7fm-d
POD=$(sk -n "$NS" get pods 2>/dev/null | grep -av memcache | grep oauth2-proxy | grep Running | awk '{print $1}' | head -1)
echo "pod=$POD"
echo "=== fire a request, then dump the fresh oauth2-proxy log lines ==="
sk -n "$NS" run pk-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet -- \
  curl -sS -o /dev/null -w 'code=%{http_code}\n' -H 'Host: 25veqwflh7syq7fm-d.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu' -H 'X-Forwarded-Proto: https' http://oauth2-proxy:8080/ 2>&1 | grep -av memcache
sleep 2
sk -n "$NS" logs "$POD" --tail=15 2>&1 | grep -av memcache | tail -12
echo "=== does it have --reverse-proxy / --skip-provider-button / --whitelist-domain ? ==="
sk -n "$NS" get deploy oauth2-proxy -o jsonpath='{.spec.template.spec.containers[0].args}' 2>&1 | grep -av memcache | tr ',' '\n' | grep -iE 'reverse-proxy|whitelist|skip-provider|skip-auth|set-xauth|pass-host'
echo "(if reverse-proxy absent, that's likely the 403 cause when behind the gateway)"
echo "=== also: can oauth2-proxy reach keycloak's OIDC endpoints in-cluster? ==="
sk -n "$NS" run pj-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet -- \
  curl -sS -o /dev/null -w 'keycloak issuer: http=%{http_code}\n' http://keycloak:8080/keycloak/realms/ai-trust/.well-known/openid-configuration 2>&1 | grep -av memcache
