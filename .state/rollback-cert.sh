#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"; LB=130.214.18.166
echo "=== ROLLBACK: restore the original self-signed domain-certificate secret (frontproxy trusts it) ==="
kubectl -n platform-mesh-system apply -f .state/backup-cert-swap/secrets.yaml 2>&1 | grep -av memcache
echo "=== restart traefik to serve the restored cert ==="
kubectl -n default rollout restart deploy/traefik 2>&1 | grep -av memcache
kubectl -n default rollout status deploy/traefik --timeout=120s 2>&1 | grep -av memcache | tail -1
echo "=== restart frontproxy so its OIDC authenticator re-initializes against the restored (trusted) cert ==="
kubectl -n platform-mesh-system rollout restart deploy/frontproxy-front-proxy 2>&1 | grep -av memcache
kubectl -n platform-mesh-system rollout status deploy/frontproxy-front-proxy --timeout=120s 2>&1 | grep -av memcache | tail -1
sleep 15
echo "=== VERIFY: served cert back to self-signed ==="
kubectl -n platform-mesh-system run rb-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet -- \
  curl -ksv --resolve ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu:443:$LB https://ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu/ 2>&1 | grep -av memcache | grep -iE 'issuer:' | head -1
echo "=== VERIFY: frontproxy OIDC errors gone? (watch 20s) ==="
sleep 20
kubectl -n platform-mesh-system logs deploy/frontproxy-front-proxy --since=40s 2>&1 | grep -av memcache | grep -cE 'x509|unknown authority|failed to verify'
echo "  ^ 0 = OIDC trust restored"
echo "=== VERIFY: TokenReview 401s stopped? ==="
kubectl -n platform-mesh-system logs deploy/kubernetes-graphql-gateway --since=40s 2>&1 | grep -av memcache | grep -c 'TokenReview API call failed'
