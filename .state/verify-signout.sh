cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"

NS=aitrust-mt-msp

# url-encoded keycloak logout URL
KC_LOGOUT='https://ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu/keycloak/realms/fridaytest/protocol/openid-connect/logout?post_logout_redirect_uri=https://ai-trust-mt-fridaytest.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu&client_id=aitrust-mt-app'

# url-encode it
ENC=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=''))" "$KC_LOGOUT")

SIGNOUT="http://oauth2-proxy-fridaytest.${NS}.svc.cluster.local:8080/oauth2/sign_out?rd=${ENC}"

echo "=== signout URL ==="
echo "$SIGNOUT"
echo "==================="

POD=curl-signout-$RANDOM
kubectl run "$POD" -n "$NS" --restart=Never --image=curlimages/curl:8.9.1 \
  --command -- sleep 120 2>&1 | grep -avi memcache

kubectl wait --for=condition=Ready pod/"$POD" -n "$NS" --timeout=60s 2>&1 | grep -avi memcache

echo "=== curl -i (headers) ==="
kubectl exec -n "$NS" "$POD" -- curl -s -i -o - -w "\n---FINAL_HTTP_CODE:%{http_code}\n" "$SIGNOUT" 2>&1 | grep -avi memcache

kubectl delete pod "$POD" -n "$NS" --grace-period=0 --force 2>&1 | grep -avi memcache
