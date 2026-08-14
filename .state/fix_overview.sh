#!/bin/bash
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh 2>/dev/null; load_config 2>/dev/null
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
f(){ grep -avi memcache; }
SRC="$BUNDLE/../ai-trust-platform-git"
PUB="https://$SHARED_APP_HOST"

echo "=== rebuild overview-frontend WITH VITE_USERS_API_BASE (from $(git -C "$SRC" rev-parse --short HEAD)) ==="
cd "$SRC"
docker build -q -t aitrust/overview-frontend:build \
  --build-arg VITE_OVERVIEW_API_BASE=/api/overview/v1 \
  --build-arg VITE_ALERTS_API_BASE=/api/alerts/v1 \
  --build-arg VITE_ALERTS_URL=$PUB/alerts \
  --build-arg VITE_REGISTRY_URL=$PUB/registry \
  --build-arg VITE_COMPLIANCE_URL=$PUB/compliance \
  --build-arg VITE_COMPLIANCE_API_BASE=/api/compliance/v1 \
  --build-arg VITE_USERS_API_BASE=/api/users/v1 \
  ./overview/frontend
echo "=== push ==="
docker tag aitrust/overview-frontend:build "$REGISTRY/aitrust-overview-frontend:$TAG"
docker push -q "$REGISTRY/aitrust-overview-frontend:$TAG" && echo "  pushed $REGISTRY/aitrust-overview-frontend:$TAG"
echo "=== roll ==="
cd "$BUNDLE"
kubectl -n "$NS" rollout restart deploy/overview-frontend 2>&1 | f
kubectl -n "$NS" rollout status deploy/overview-frontend --timeout=180s 2>&1 | f | tail -1
echo "=== VERIFY overview bundle now has api/users/v1 and NO missing-env throw ==="
sleep 3
kubectl -n "$NS" exec deploy/overview-frontend -- sh -c 'echo "users token: $(grep -rhoE "api/users/v1" /usr/share/nginx/html/assets/*.js 2>/dev/null | sort -u | head -1)"; grep -rIl "Missing required environment variable" /usr/share/nginx/html/assets/ 2>/dev/null | head -1 && echo "  STILL THROWS" || echo "  no missing-env throw (good)"' 2>&1 | f
echo DONE
