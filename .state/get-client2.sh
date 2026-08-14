cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"

TOKEN=$(cat /tmp/kc_token.txt)
KC="http://keycloak-service.platform-mesh-system.svc.cluster.local:8080/keycloak"
REALM="fridaytest"
CLIENTID="aitrust-mt-app"

kubectl -n aitrust-mt-msp run kc-getc-$$ --rm -i --restart=Never \
  --image=curlimages/curl:8.9.1 \
  --env="TOKEN=$TOKEN" --env="KC=$KC" --env="REALM=$REALM" --env="CLIENTID=$CLIENTID" \
  --command -- sh -c '
    echo "=== token check: list realms ==="
    curl -s -H "Authorization: Bearer $TOKEN" "$KC/admin/realms" -w "\nHTTP %{http_code}\n" -o /tmp/realms.json
    grep -o "\"realm\":\"[^\"]*\"" /tmp/realms.json | head -20
    echo "=== client lookup ==="
    curl -s -H "Authorization: Bearer $TOKEN" "$KC/admin/realms/$REALM/clients?clientId=$CLIENTID" -w "HTTP %{http_code}\n"
  ' 2>&1 | grep -avi memcache
