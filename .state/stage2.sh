#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
LB=130.214.18.166
probe(){ # host
  sk -n platform-mesh-system run v-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet -- \
    sh -c "echo | openssl s_client -connect $LB:443 -servername $1 2>/dev/null | openssl x509 -noout -issuer" 2>&1 | grep -av memcache | grep -i issuer
}
echo "=== testai (should now be Let's Encrypt) ==="
probe testai.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu
echo "=== instance d (should STILL be self-signed, via terminate-wildstar, unchanged) ==="
probe 25veqwflh7syq7fm-d.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu
echo "=== portal host (should STILL be self-signed, unaffected) ==="
probe aitrustg2.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu
echo "=== testai app reachable + verifies against public trust store (NO -k)? ==="
sk -n platform-mesh-system run vt-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet -- \
  curl -sS -o /dev/null -w 'testai https (verified): http=%{http_code}\n' \
  --resolve testai.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu:443:$LB \
  https://testai.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu/ 2>&1 | grep -av memcache | grep -E 'http=|SSL|certificate'
