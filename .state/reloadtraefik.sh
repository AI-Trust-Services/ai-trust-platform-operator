#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"; LB=130.214.18.166
echo "=== restart traefik so it reloads the Gateway (picks up cert-p1) ==="
kubectl -n default rollout restart deploy/traefik 2>&1 | grep -av memcache
kubectl -n default rollout status deploy/traefik --timeout=120s 2>&1 | grep -av memcache | tail -1
sleep 8
echo "=== re-verify served issuer per host ==="
iss(){ kubectl -n platform-mesh-system run z-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet -- \
  curl -ksv --resolve "$1:443:$LB" "https://$1/" 2>&1 | grep -av memcache | grep -iE 'issuer:|subject:' | head -2; }
echo "-- testai (instance, terminate-wildstar -> cert-p1: expect Lets Encrypt) --"; iss testai.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu
echo "-- d (instance: expect Lets Encrypt) --"; iss 25veqwflh7syq7fm-d.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu
echo "-- apex (terminate, untouched: expect self-signed) --"; iss ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu
echo "=== verified fetch (no -k) for testai ==="
kubectl -n platform-mesh-system run zz-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet -- \
  curl -sS -o /dev/null -w 'testai verified: http=%{http_code}\n' --resolve testai.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu:443:$LB https://testai.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu/ 2>&1 | grep -av memcache | grep -E 'http=|SSL'
