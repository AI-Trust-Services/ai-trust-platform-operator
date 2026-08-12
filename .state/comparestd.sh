#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
echo "=== does the WORKING standalone app (Standard_Ai_Platform) also return 403 sign-in page on / ? ==="
STD=ai-trust-platform-main.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu
sk -n platform-mesh-system run pstd-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet -- \
  curl -sk -o /dev/null -w 'standalone GET / : http=%{http_code} -> %{redirect_url}\n' -H 'Accept: text/html' "https://$STD/" 2>&1 | grep -av memcache
echo "=== compare the first 200 chars of body: standalone vs instance d ==="
echo "--- standalone ---"
sk -n platform-mesh-system run ps2-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet -- \
  curl -sk -H 'Accept: text/html' "https://$STD/" 2>&1 | grep -av memcache | grep -oiE '<title>[^<]*</title>|Sign In|OpenID|AI Trust Platform' | head -3
echo "--- instance d ---"
H=25veqwflh7syq7fm-d.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu
sk -n platform-mesh-system run pd2-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet -- \
  curl -sk -H 'Accept: text/html' "https://$H/" 2>&1 | grep -av memcache | grep -oiE '<title>[^<]*</title>|Sign In|OpenID|AI Trust Platform' | head -3
