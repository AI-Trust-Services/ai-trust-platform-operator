cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"

NS=aitrust-mt-msp
KC="http://keycloak-service.platform-mesh-system.svc.cluster.local:8080/keycloak/realms/fridaytest/protocol/openid-connect/logout"
REDIR_NOSLASH="https://ai-trust-mt-fridaytest.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu"
REDIR_SLASH="${REDIR_NOSLASH}/"
CLIENT="aitrust-mt-app"

POD=kc-logout-test

kubectl -n "$NS" delete pod "$POD" --ignore-not-found --grace-period=0 --force 2>/dev/null | grep -avi memcache

kubectl -n "$NS" run "$POD" --image=curlimages/curl:8.9.1 --restart=Never --command -- sleep 300 2>&1 | grep -avi memcache
kubectl -n "$NS" wait --for=condition=Ready pod/"$POD" --timeout=90s 2>&1 | grep -avi memcache

echo "===== TEST 1: no trailing slash ====="
kubectl -n "$NS" exec "$POD" -- sh -c "curl -sS -o /dev/null -D - \"${KC}?post_logout_redirect_uri=${REDIR_NOSLASH}&client_id=${CLIENT}\"" 2>&1 | grep -avi memcache

echo ""
echo "===== TEST 2: trailing slash ====="
kubectl -n "$NS" exec "$POD" -- sh -c "curl -sS -o /dev/null -D - \"${KC}?post_logout_redirect_uri=${REDIR_SLASH}&client_id=${CLIENT}\"" 2>&1 | grep -avi memcache

echo ""
echo "===== TEST 3: body (no redirect) to detect confirmation/error page ====="
kubectl -n "$NS" exec "$POD" -- sh -c "curl -sS \"${KC}?post_logout_redirect_uri=${REDIR_NOSLASH}&client_id=${CLIENT}\" | head -c 2000" 2>&1 | grep -avi memcache

echo ""
kubectl -n "$NS" delete pod "$POD" --ignore-not-found --grace-period=0 --force 2>/dev/null | grep -avi memcache
