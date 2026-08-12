#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
LB=130.214.18.166
echo "=== instance host via curl WITHOUT -k (real cert => http code, self-signed => SSL error) ==="
for H in 25veqwflh7syq7fm-d.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu \
         testai.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu; do
  sk -n platform-mesh-system run c-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet -- \
    curl -sS -o /dev/null -w "$H : verified http=%{http_code}\n" --resolve "$H:443:$LB" "https://$H/" 2>&1 | grep -av memcache | grep -E 'http=|SSL|certificate'
done
echo "=== apex (terminate listener, UNTOUCHED — should STILL be self-signed => SSL error) ==="
A=ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu
sk -n platform-mesh-system run ca-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet -- \
  curl -sS -o /dev/null -w "$A : verified http=%{http_code}\n" --resolve "$A:443:$LB" "https://$A/" 2>&1 | grep -av memcache | grep -E 'http=|SSL|certificate'
echo "=== issuer via curl -v (grep the server cert issuer line) for testai ==="
sk -n platform-mesh-system run cv-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet -- \
  curl -kv --resolve testai.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu:443:$LB https://testai.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu/ 2>&1 | grep -av memcache | grep -iE 'issuer:|subject:|SSL certificate verify' | head
