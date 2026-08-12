#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
NS=aitp-25veqwflh7syq7fm-d
echo "=== add --reverse-proxy=true to the live oauth2-proxy args (test the fix) ==="
sk -n "$NS" patch deploy oauth2-proxy --type=json -p '[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--reverse-proxy=true"}]' 2>&1 | grep -av memcache
sk -n "$NS" rollout status deploy/oauth2-proxy --timeout=90s 2>&1 | grep -av memcache | tail -1
echo "=== test: request / with forwarded headers (expect 302 -> keycloak, NOT 403) ==="
sk -n "$NS" run pr-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet -- \
  curl -sS -o /dev/null -w 'http=%{http_code} redirect=%{redirect_url}\n' \
  -H 'Host: 25veqwflh7syq7fm-d.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu' \
  -H 'X-Forwarded-Proto: https' \
  -H 'X-Forwarded-Host: 25veqwflh7syq7fm-d.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu' \
  http://oauth2-proxy:8080/ 2>&1 | grep -av memcache
