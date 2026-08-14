#!/bin/bash
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh 2>/dev/null; load_config 2>/dev/null
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
f(){ grep -avi memcache; }
SRC="$BUNDLE/../ai-trust-platform-git"
PUB="https://$SHARED_APP_HOST"

echo "=== rebuild overview-frontend --no-cache (force npm run build to see VITE_USERS_API_BASE) ==="
cd "$SRC"
docker build --no-cache -t aitrust/overview-frontend:build \
  --build-arg VITE_OVERVIEW_API_BASE=/api/overview/v1 \
  --build-arg VITE_ALERTS_API_BASE=/api/alerts/v1 \
  --build-arg VITE_ALERTS_URL=$PUB/alerts \
  --build-arg VITE_REGISTRY_URL=$PUB/registry \
  --build-arg VITE_COMPLIANCE_URL=$PUB/compliance \
  --build-arg VITE_COMPLIANCE_API_BASE=/api/compliance/v1 \
  --build-arg VITE_USERS_API_BASE=/api/users/v1 \
  ./overview/frontend 2>&1 | tail -6
echo "=== push + roll ==="
docker tag aitrust/overview-frontend:build "$REGISTRY/aitrust-overview-frontend:$TAG"
docker push -q "$REGISTRY/aitrust-overview-frontend:$TAG" && echo "  pushed"
cd "$BUNDLE"
kubectl -n "$NS" rollout restart deploy/overview-frontend 2>&1 | f
kubectl -n "$NS" rollout status deploy/overview-frontend --timeout=180s 2>&1 | f | tail -1

echo "=== VERIFY: does the runtime env object include the users base value? (search for the VALUE, not the key) ==="
sleep 3
kubectl -n "$NS" exec deploy/overview-frontend -- sh -c '
  BUNDLE=$(ls /usr/share/nginx/html/assets/*.js | head -1)
  echo "  bundle: $BUNDLE"
  # Vite emits an env object like {..."VITE_USERS_API_BASE":"/api/users/v1"...}. Look for that pairing.
  grep -oE "VITE_USERS_API_BASE\"?:\"?/api/users/v1|/api/users/v1" "$BUNDLE" 2>/dev/null | sort -u | sed "s/^/    match: /" | head
' 2>&1 | f
echo DONE
