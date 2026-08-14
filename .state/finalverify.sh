#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp; LB=130.214.18.166
H=ai-trust-mt-mttest.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu

echo "=== 1. ALL backend pods healthy on new images + MODE=jwt ==="
kubectl -n "$NS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep -E 'backend|worker|shell|consumer|minio|clickhouse' | grep -vE 'Completed' | awk '{printf "%-52s %-6s %s\n",$1,$2,$3}'
kubectl -n "$NS" exec deploy/ai-system-registry-backend -- sh -lc 'python -c "from ai_trust_tenancy.config import MODE,JWKS_ISSUER_BASE,JWT_VERIFY; print(\"MODE=%s VERIFY=%s BASE_set=%s\"%(MODE,JWT_VERIFY,bool(JWKS_ISSUER_BASE)))"' 2>&1 | grep -avi memcache | head

echo "=== 2. SEC-M1: RLS WITH CHECK is write-own (no OR NULL) ==="
PGPOD=$(kubectl -n "$NS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep -E '^postgres' | awk '{print $1}' | head -1)
kubectl -n "$NS" exec "$PGPOD" -- sh -lc "PGPASSWORD=\$POSTGRES_PASSWORD psql -U \$POSTGRES_USER -d ai_trust -tA -c \"SELECT policyname||' USING='||qual||' CHECK='||with_check FROM pg_policies WHERE tablename='ai_systems'\"" 2>&1 | grep -avi memcache | head

echo "=== 3. SEC-M1 live: as ai_trust_app tenantA, writing a NULL-tenant row must FAIL ==="
kubectl -n "$NS" exec "$PGPOD" -- sh -lc "PGPASSWORD=apppw psql -U ai_trust_app -d ai_trust -tA -c \"SET app.current_tenant='tA'; INSERT INTO ai_systems (id,name,tier,tenant_id) VALUES ('SYS-CHK1','x','minimal',NULL);\"" 2>&1 | grep -avi memcache | grep -iE 'ERROR|INSERT' | head -1
echo "   (expect: ERROR ... row-level security)"

echo "=== 4. SEC-H: security headers served by shell on an app path (via oauth2 it's behind auth; check shell directly) ==="
kubectl -n "$NS" exec deploy/shell -- sh -lc 'wget -qS -O /dev/null http://localhost/ 2>&1 | grep -iE "Content-Security-Policy|Strict-Transport|X-Content-Type|Referrer-Policy|X-Frame" | head' 2>&1 | grep -avi memcache | head

echo "=== 5. SEC-C1 live: /oauth2/start still 302s to the mttest realm (login intact) ==="
kubectl -n "$NS" run s-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet --command -- \
  sh -c "curl -sk -o /dev/null -w 'start http=%{http_code}\n' --resolve $H:443:$LB 'https://$H/oauth2/start?rd=%2F'" 2>&1 | grep -avi memcache | grep http=

echo "=== 6. cleanup test row ==="
kubectl -n "$NS" exec "$PGPOD" -- sh -lc "PGPASSWORD=\$POSTGRES_PASSWORD psql -U \$POSTGRES_USER -d ai_trust -c \"DELETE FROM ai_systems WHERE id='SYS-CHK1'\"" 2>&1 | grep -avi memcache | head -1
echo DONE
