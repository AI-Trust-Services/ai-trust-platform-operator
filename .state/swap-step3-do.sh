#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"; LB=130.214.18.166
echo "=== SWAP: overwrite domain-certificate secret data with cert-aitrust-full's LE material ==="
CRT=$(kubectl -n platform-mesh-system get secret cert-aitrust-full -o jsonpath='{.data.tls\.crt}' 2>/dev/null)
KEY=$(kubectl -n platform-mesh-system get secret cert-aitrust-full -o jsonpath='{.data.tls\.key}' 2>/dev/null)
CA=$(kubectl -n platform-mesh-system get secret cert-aitrust-full -o jsonpath='{.data.ca\.crt}' 2>/dev/null)
[ -n "$CRT" ] && [ -n "$KEY" ] || { echo "LE secret empty — ABORT"; exit 1; }
kubectl -n platform-mesh-system patch secret domain-certificate --type=merge -p "{\"data\":{\"tls.crt\":\"$CRT\",\"tls.key\":\"$KEY\",\"ca.crt\":\"$CA\"}}" 2>&1 | grep -av memcache
echo "=== restart traefik so it reloads the updated secret ==="
kubectl -n default rollout restart deploy/traefik 2>&1 | grep -av memcache
kubectl -n default rollout status deploy/traefik --timeout=120s 2>&1 | grep -av memcache | tail -1
sleep 8
echo "=== VERIFY served issuer per host (expect Lets Encrypt everywhere now) ==="
for H in ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu \
         aitrustg2.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu \
         25veqwflh7syq7fm-d.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu \
         testai.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu; do
  R=$(kubectl -n platform-mesh-system run v-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet -- curl -ksv --resolve "$H:443:$LB" "https://$H/" 2>&1 | grep -av memcache | grep -iE 'issuer:' | head -1)
  echo "  $H -> $R"
done
echo "=== verified fetch (NO -k) for an instance + apex ==="
for H in aitrustg2.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu 25veqwflh7syq7fm-d.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu; do
  kubectl -n platform-mesh-system run w-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet -- curl -sS -o /dev/null -w "$H verified: http=%{http_code}\n" --resolve "$H:443:$LB" "https://$H/" 2>&1 | grep -av memcache | grep -E 'http=|SSL'
done
