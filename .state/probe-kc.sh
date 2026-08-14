cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"

TOKEN=$(cat /tmp/kc_token.txt)
KC="http://keycloak-service.platform-mesh-system.svc.cluster.local:8080"

kubectl -n aitrust-mt-msp run kc-probe-$$ --rm -i --restart=Never \
  --image=curlimages/curl:8.9.1 \
  --env="TOKEN=$TOKEN" --env="KC=$KC" \
  --command -- sh -c '
    echo "=== root (base path?) ==="
    curl -s -o /dev/null -w "HTTP %{http_code}\n" "$KC/"
    echo "=== /realms/master well-known ==="
    curl -s -o /dev/null -w "HTTP %{http_code}\n" "$KC/realms/master/.well-known/openid-configuration"
    echo "=== /auth/realms/master well-known (legacy path) ==="
    curl -s -o /dev/null -w "HTTP %{http_code}\n" "$KC/auth/realms/master/.well-known/openid-configuration"
    echo "=== /realms/fridaytest well-known ==="
    curl -s -o /dev/null -w "HTTP %{http_code}\n" "$KC/realms/fridaytest/.well-known/openid-configuration"
    echo "=== admin list realms (token check) ==="
    curl -s -H "Authorization: Bearer $TOKEN" "$KC/admin/realms" -w "\nHTTP %{http_code}\n" | head -c 400
    echo ""
  ' 2>&1 | grep -avi memcache
