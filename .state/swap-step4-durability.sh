#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"; LB=130.214.18.166
echo "=== 1) portal + keycloak/dex reachable over the new cert (verified, no -k)? ==="
for path in / /keycloak/realms/master; do
  kubectl -n platform-mesh-system run p-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet -- \
    curl -sS -o /dev/null -w "apex$path verified: http=%{http_code}\n" --resolve ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu:443:$LB "https://ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu$path" 2>&1 | grep -av memcache | grep -E 'http=|SSL'
done
echo "=== 2) does the overwrite HOLD after ~90s (Flux could re-assert if it owned the secret)? ==="
sleep 90
ISS=$(kubectl -n platform-mesh-system run h-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet -- curl -ksv --resolve aitrustg2.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu:443:$LB https://aitrustg2.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu/ 2>&1 | grep -av memcache | grep -iE 'issuer:' | head -1)
echo "  after 90s, aitrustg2 issuer: $ISS"
echo "  (expect still Lets Encrypt — if it flipped back to Local CA, Flux/gardener re-asserted and we need the durable HelmRelease approach)"
echo "=== 3) is domain-certificate now backed by a gardener Certificate that could renew/overwrite it? ==="
kubectl -n platform-mesh-system get certificate.cert.gardener.cloud 2>&1 | grep -av memcache | grep -iE 'NAME|domain-certificate|aitrust-full'
