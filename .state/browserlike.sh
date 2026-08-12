#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
NS=aitp-25veqwflh7syq7fm-d
H=25veqwflh7syq7fm-d.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu
echo "=== browser-like request (Accept: text/html) — expect 302 to keycloak, NOT 403 ==="
sk -n "$NS" run pb-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet -- \
  curl -sS -o /dev/null -w 'GET / (html): %{http_code} -> %{redirect_url}\n' \
  -H "Host: $H" -H 'X-Forwarded-Proto: https' -H 'Accept: text/html,application/xhtml+xml' \
  http://oauth2-proxy:8080/ 2>&1 | grep -av memcache
echo "=== external through the gateway, browser-like (does DNS resolve + gateway route now?) ==="
sk -n platform-mesh-system run pg-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet -- \
  curl -sk -o /dev/null -w 'external GET / (html): %{http_code} -> %{redirect_url}\n' \
  -H 'Accept: text/html' "https://$H/" 2>&1 | grep -av memcache
echo "=== does the new host resolve in-cluster DNS at all? ==="
sk -n platform-mesh-system run pn-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet -- \
  sh -c "nslookup $H 2>&1 | tail -4 || getent hosts $H" 2>&1 | grep -av memcache | tail -5
