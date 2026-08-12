#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
URL=https://q3c0weh7suf5hgjk-my-aitrust.aitrust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu
echo "=== external reachability of the instance URL (expect 302 -> keycloak login) ==="
sk -n platform-mesh-system run aitrusthit-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet -- \
  curl -sk -o /dev/null -w 'http=%{http_code} redirect=%{redirect_url}\n' "$URL/" 2>&1 | grep -av memcache | head
echo "=== keycloak bypass path ==="
sk -n platform-mesh-system run aitrustkc-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet -- \
  curl -sk -o /dev/null -w 'http=%{http_code}\n' "$URL/keycloak/realms/ai-trust" 2>&1 | grep -av memcache | head
