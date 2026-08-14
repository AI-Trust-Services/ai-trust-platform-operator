cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"

TOKEN=$(cat /tmp/kc_token.txt)
if [ -z "$TOKEN" ]; then echo "ERROR: no token"; exit 1; fi

KC="http://keycloak-service.platform-mesh-system.svc.cluster.local:8080"
REALM="fridaytest"
CLIENTID="aitrust-mt-app"

kubectl -n aitrust-mt-msp run kc-verify-$$ --rm -i --restart=Never \
  --image=curlimages/curl:8.9.1 \
  --env="TOKEN=$TOKEN" --env="KC=$KC" --env="REALM=$REALM" --env="CLIENTID=$CLIENTID" \
  --command -- sh -c '
    # 1. find internal id of the client by clientId
    REP=$(curl -s -H "Authorization: Bearer $TOKEN" "$KC/admin/realms/$REALM/clients?clientId=$CLIENTID")
    echo "=== CLIENT LOOKUP (clientId=$CLIENTID) ==="
    echo "$REP"
  ' 2>&1 | grep -avi memcache
