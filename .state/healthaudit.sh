#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
echo "=== 1. ALL pods healthy? (anything not Running/Completed) ==="
kubectl -n "$NS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep -vE 'Running|Completed' | awk '{printf "  %-52s %-6s %s\n",$1,$2,$3}' || true
echo "  (empty above = all healthy)"
kubectl -n "$NS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep -cE 'Running' | xargs echo "  running pods:"

echo "=== 2. worker: is it doing per-tenant passes now (tenancy on)? OWNER_DATABASE_URL set? ==="
kubectl -n "$NS" get deploy policy-checker-worker -o jsonpath='{range .spec.template.spec.containers[0].env[*]}{.name}{"="}{.value}{"\n"}{end}' 2>&1 | grep -avi memcache | grep -iE 'TENANCY_MODE|OWNER_DATABASE|TENANT_CLAIM'
kubectl -n "$NS" logs deploy/policy-checker-worker --tail=15 2>&1 | grep -avi memcache | grep -iE 'tenant_pass|evaluating|error|owner|unscoped' | tail -6

echo "=== 3. all backends actually on MODE=jwt with JWKS base? ==="
for d in ai-system-registry-backend monitoring-backend overview-backend alerts-backend compliance-backend decision-trace-analyzer-backend users-backend; do
  m=$(kubectl -n "$NS" get deploy $d -o jsonpath='{range .spec.template.spec.containers[0].env[?(@.name=="TENANCY_MODE")]}{.value}{end}' 2>/dev/null | grep -avi memcache)
  j=$(kubectl -n "$NS" get deploy $d -o jsonpath='{range .spec.template.spec.containers[0].env[?(@.name=="TENANCY_JWKS_ISSUER_BASE")]}{.value}{end}' 2>/dev/null | grep -avi memcache)
  echo "  $d: MODE=$m JWKS=$([ -n "$j" ] && echo set || echo MISSING)"
done

echo "=== 4. clickhouse consumer: is it stamping tenant_id? recent spans have tenant? ==="
CHPOD=$(kubectl -n "$NS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep -E '^clickhouse-[0-9a-f]' | awk '{print $1}' | head -1)
kubectl -n "$NS" exec "$CHPOD" -- clickhouse-client -q "SELECT tenant_id, count() FROM otel.gen_ai_spans GROUP BY tenant_id ORDER BY 2 DESC LIMIT 5" 2>&1 | grep -avi memcache | head
echo DONE
