#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp; LB=130.214.18.166
H=ai-trust-mt-mttest.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu

echo "=== A. security headers on the edge (SEC-H1/2/3) ==="
kubectl -n "$NS" run h-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet --command -- \
  sh -c "curl -sk -D - -o /dev/null --resolve $H:443:$LB https://$H/oauth2/sign_in | grep -iE 'content-security-policy|x-frame-options|strict-transport|x-content-type|referrer-policy|access-control-allow-origin'" 2>&1 | grep -avi memcache | head

echo "=== B. jwt-verify env present on registry backend (SEC-C2) ==="
kubectl -n "$NS" get deploy ai-system-registry-backend -o jsonpath='{range .spec.template.spec.containers[0].env[*]}{.name}={.value}{"\n"}{end}' 2>&1 | grep -avi memcache | grep -iE 'TENANCY_MODE|JWKS|TENANT_CLAIM'

echo "=== C. resolver code in the RUNNING image ignores X-Tenant-Id in jwt mode (SEC-C1) ==="
kubectl -n "$NS" exec deploy/ai-system-registry-backend -- sh -lc 'python -c "
import ai_trust_tenancy.resolver as r, inspect
src=inspect.getsource(r.resolve_tenant)
print(\"header-only-in-header-mode:\", \"MODE == \x27header\x27\" in src and \"_verify_and_decode\" in src)
print(\"has JWKS verify:\", hasattr(r, \"_verify_and_decode\"))
"' 2>&1 | grep -avi memcache | head

echo "=== D. nginx strips inbound X-Tenant-Id (SEC-C1) ==="
kubectl -n "$NS" exec deploy/shell -- sh -lc 'grep -c "X-Tenant-Id \"\"" /etc/nginx/conf.d/default.conf 2>/dev/null || grep -c "X-Tenant-Id \"\"" /etc/nginx/nginx.conf' 2>&1 | grep -avi memcache | head -1

echo "=== E. RLS policy is now write-own (SEC-M1) ==="
PGPOD=$(kubectl -n "$NS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep -E '^postgres' | awk '{print $1}' | head -1)
kubectl -n "$NS" exec "$PGPOD" -- sh -lc "PGPASSWORD=\$POSTGRES_PASSWORD psql -U \$POSTGRES_USER -d ai_trust -tA -c \"SELECT with_check FROM pg_policies WHERE tablename='ai_systems' AND policyname='tenant_isolation'\"" 2>&1 | grep -avi memcache | head
echo DONE
