cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh
load_config
export KUBECONFIG=""

echo "### B2) DIRECT to RUNNING keycloak bare /realms with proper --data-urlencode fields, bogus pw"
kubectl -n ai-trust-app exec deploy/shell -- sh -c 'curl -s -w "\nHTTP=%{http_code}\n" -X POST http://keycloak:8080/realms/master/protocol/openid-connect/token --data-urlencode grant_type=password --data-urlencode client_id=admin-cli --data-urlencode username=admin --data-urlencode password=BOGUSTEST' 2>&1 | grep -avi memcache

echo ""
echo "### D) Confirm running KC has NO /keycloak (GET realms/master both paths)"
kubectl -n ai-trust-app exec deploy/shell -- sh -c "curl -s -o /dev/null -w \"bare /realms/master GET=%{http_code}\n\" http://keycloak:8080/realms/master; curl -s -o /dev/null -w \"/keycloak/realms/master GET=%{http_code}\n\" http://keycloak:8080/keycloak/realms/master" 2>&1 | grep -avi memcache
