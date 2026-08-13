cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh
load_config
export KUBECONFIG=""

BODY="grant_type=password&client_id=admin-cli&username=admin&password=BOGUSTEST"

echo "### A) DIRECT to keycloak WITH relative path /keycloak (expect: KC responds, invalid_grant since bogus pw / or realm existence)"
kubectl -n ai-trust-app exec deploy/shell -- sh -c "curl -s -o /tmp/a.txt -w \"HTTP=%{http_code}\n\" -X POST http://keycloak:8080/keycloak/realms/master/protocol/openid-connect/token -H \"Content-Type: application/x-www-form-urlencoded\" -d \"\"; echo BODY:; cat /tmp/a.txt" 2>&1 | grep -avi memcache

echo ""
echo "### B) DIRECT to keycloak WITHOUT relative path (bare /realms) — expect 404 (KC serves under /keycloak)"
kubectl -n ai-trust-app exec deploy/shell -- sh -c "curl -s -o /tmp/b.txt -w \"HTTP=%{http_code}\n\" -X POST http://keycloak:8080/realms/master/protocol/openid-connect/token -H \"Content-Type: application/x-www-form-urlencoded\" -d \"\"; echo BODY:; head -c 300 /tmp/b.txt; echo" 2>&1 | grep -avi memcache

echo ""
echo "### C) VIA shell service http://shell:80/keycloak/... (what shell nginx does with /keycloak)"
kubectl -n ai-trust-app exec deploy/shell -- sh -c "curl -s -o /tmp/c.txt -w \"HTTP=%{http_code}\n\" -X POST http://shell:80/keycloak/realms/master/protocol/openid-connect/token -H \"Content-Type: application/x-www-form-urlencoded\" -d \"\"; echo BODY:; head -c 300 /tmp/c.txt; echo" 2>&1 | grep -avi memcache
