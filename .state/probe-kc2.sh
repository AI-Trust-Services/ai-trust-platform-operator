cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"

TOKEN=$(cat /tmp/kc_token.txt)
KC="http://keycloak-service.platform-mesh-system.svc.cluster.local:8080"

kubectl -n aitrust-mt-msp run kc-probe2-$$ --rm -i --restart=Never \
  --image=curlimages/curl:8.9.1 \
  --env="TOKEN=$TOKEN" --env="KC=$KC" \
  --command -- sh -c '
    echo "=== root headers (Location) ==="
    curl -s -D - -o /dev/null "$KC/" | grep -i "^location:"
    echo "=== try /auth/ base ==="
    curl -s -o /dev/null -w "HTTP %{http_code}\n" "$KC/auth/"
    curl -s -o /dev/null -w "HTTP %{http_code}\n" "$KC/auth/realms/master/.well-known/openid-configuration"
    echo "=== admin realms under /auth ==="
    curl -s -H "Authorization: Bearer $TOKEN" "$KC/auth/admin/realms" -w "\nHTTP %{http_code}\n" | head -c 300
    echo ""
  ' 2>&1 | grep -avi memcache
