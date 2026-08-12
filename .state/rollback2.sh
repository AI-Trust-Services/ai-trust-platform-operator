#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"; LB=130.214.18.166
echo "=== restore domain-certificate self-signed bytes from prerequisites/tls.* (authoritative source) ==="
# prerequisites/tls.crt (leaf+CA chain) and tls.key are the original self-signed material used to seed the secret.
kubectl -n platform-mesh-system create secret tls domain-certificate \
  --cert=prerequisites/tls.crt --key=prerequisites/tls.key \
  --dry-run=client -o yaml | kubectl apply -f - 2>&1 | grep -av memcache
# also set ca.crt if the secret needs it (tls.crt already contains the chain)
echo "=== restart traefik + frontproxy to reload ==="
kubectl -n default rollout restart deploy/traefik 2>&1 | grep -av memcache
kubectl -n default rollout status deploy/traefik --timeout=120s 2>&1 | grep -av memcache | tail -1
kubectl -n platform-mesh-system rollout restart deploy/frontproxy-front-proxy 2>&1 | grep -av memcache
kubectl -n platform-mesh-system rollout status deploy/frontproxy-front-proxy --timeout=120s 2>&1 | grep -av memcache | tail -1
sleep 20
echo "=== served cert now (expect self-signed CN=ai-trust-1-mesh / Local CA) ==="
kubectl -n platform-mesh-system run rb2-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet -- \
  curl -ksv --resolve ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu:443:$LB https://ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu/ 2>&1 | grep -av memcache | grep -iE 'issuer:|subject:' | head -2
echo "=== frontproxy x509 errors in last 40s (expect 0) ==="
sleep 20
kubectl -n platform-mesh-system logs deploy/frontproxy-front-proxy --since=40s 2>&1 | grep -av memcache | grep -cE 'x509|unknown authority|failed to verify'
echo "=== TokenReview failures last 40s (expect 0) ==="
kubectl -n platform-mesh-system logs deploy/kubernetes-graphql-gateway --since=40s 2>&1 | grep -av memcache | grep -c 'TokenReview API call failed'
