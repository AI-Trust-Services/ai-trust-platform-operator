#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
NS=aitp-25veqwflh7syq7fm-d
echo "=== what IS the 403 body? (first 400 chars — is it the oauth2 sign-in button page?) ==="
sk -n "$NS" run pbody-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet -- \
  curl -sS -H "Host: 25veqwflh7syq7fm-d.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu" -H 'X-Forwarded-Proto: https' -H 'Accept: text/html' http://oauth2-proxy:8080/ 2>&1 | grep -av memcache | head -c 500
echo ""
echo "=== add --skip-provider-button=true so / auto-redirects (302) to keycloak ==="
sk -n "$NS" patch deploy oauth2-proxy --type=json -p '[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--skip-provider-button=true"}]' 2>&1 | grep -av memcache
sk -n "$NS" rollout status deploy/oauth2-proxy --timeout=90s 2>&1 | grep -av memcache | tail -1
echo "=== retest / (expect 302 -> keycloak now) ==="
sk -n "$NS" run pr2-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet -- \
  curl -sS -o /dev/null -w 'GET / : %{http_code} -> %{redirect_url}\n' \
  -H "Host: 25veqwflh7syq7fm-d.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu" -H 'X-Forwarded-Proto: https' -H 'Accept: text/html' \
  http://oauth2-proxy:8080/ 2>&1 | grep -av memcache
