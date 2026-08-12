#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
NS=aitp-25veqwflh7syq7fm-d
POD=$(sk -n "$NS" get pods 2>/dev/null | grep -av memcache | grep oauth2-proxy | grep Running | awk '{print $1}' | head -1)
echo "=== oauth2-proxy logs (the 403 reason) ==="
sk -n "$NS" logs "$POD" --tail=40 2>&1 | grep -av memcache | tail -30
echo "=== resolved env: APP_PUBLIC_URL / KEYCLOAK_PUBLIC_URL / ALLOWED_ORIGINS in app-config ==="
sk -n "$NS" get configmap app-config -o jsonpath='APP_PUBLIC_URL={.data.APP_PUBLIC_URL}{"\n"}KEYCLOAK_PUBLIC_URL={.data.KEYCLOAK_PUBLIC_URL}{"\n"}ALLOWED_ORIGINS={.data.ALLOWED_ORIGINS}{"\n"}' 2>&1 | grep -av memcache
echo "=== does oauth2-proxy have --reverse-proxy / --whitelist-domain / --cookie-domain? ==="
sk -n "$NS" get deploy oauth2-proxy -o jsonpath='{range .spec.template.spec.containers[0].args[*]}{@}{"\n"}{end}' 2>&1 | grep -av memcache | grep -iE 'reverse-proxy|whitelist|cookie-domain|redirect-url|login-url|upstream'
echo "=== curl / WITH the real Host header (simulate the browser through the gateway) ==="
sk -n "$NS" run p2-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet -- \
  curl -sS -o /dev/null -w 'with Host: http=%{http_code} redirect=%{redirect_url}\n' \
  -H 'Host: d.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu' \
  -H 'X-Forwarded-Proto: https' http://oauth2-proxy:8080/ 2>&1 | grep -av memcache
