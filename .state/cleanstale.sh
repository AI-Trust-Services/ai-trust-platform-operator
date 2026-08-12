#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
echo "=== delete stale routes from the deleted old instance (ns aitp-33hins0iklcwfg45-d is gone) ==="
sk -n "$GATEWAY_NS" delete httproute aitp-33hins0iklcwfg45-d-app aitp-33hins0iklcwfg45-d-keycloak --ignore-not-found 2>&1 | grep -av memcache
echo "=== verify the CORRECT host serves (through oauth2 with its own Host header) ==="
NS=aitp-25veqwflh7syq7fm-d
sk -n "$NS" run pc-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet -- \
  curl -sS -o /dev/null -w 'root via correct Host: http=%{http_code} redirect=%{redirect_url}\n' \
  -H 'Host: 25veqwflh7syq7fm-d.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu' \
  -H 'X-Forwarded-Proto: https' http://oauth2-proxy:8080/ 2>&1 | grep -av memcache
echo "=== and external through the gateway (expect 302 -> keycloak login) ==="
sk -n platform-mesh-system run pe-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet -- \
  curl -sk -o /dev/null -w 'external: http=%{http_code} redirect=%{redirect_url}\n' \
  https://25veqwflh7syq7fm-d.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu/ 2>&1 | grep -av memcache
