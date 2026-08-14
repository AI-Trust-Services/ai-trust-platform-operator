#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
CHPOD=$(kubectl -n "$NS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep -E '^clickhouse-[0-9a-f]' | awk '{print $1}' | head -1)
echo "=== ClickHouse: tenant_id distribution on gen_ai_spans (total + by tenant) ==="
kubectl -n "$NS" exec -c clickhouse "$CHPOD" -- clickhouse-client -q "SELECT count() AS total FROM otel.gen_ai_spans" 2>&1 | grep -avi memcache | head -2
kubectl -n "$NS" exec -c clickhouse "$CHPOD" -- clickhouse-client -q "SELECT tenant_id, count() FROM otel.gen_ai_spans GROUP BY tenant_id ORDER BY 2 DESC LIMIT 5 FORMAT TSV" 2>&1 | grep -avi memcache | head

echo "=== does the deployed image have the tenant_id-stamping consumer + tenant_clause? (spot-check consumer) ==="
kubectl -n "$NS" exec deploy/otel-clickhouse-consumer -- sh -lc 'grep -c "ai_trust.tenant_id" /app/consumers/clickhouse-consumer/main.py 2>/dev/null || grep -rc "ai_trust.tenant_id" /app 2>/dev/null | grep -v ":0" | head -1' 2>&1 | grep -avi memcache | head -2

echo "=== SEC-M4: is POSTGRES_PASSWORD still the default anywhere reachable? worker owner URL uses postgres:postgres ==="
echo "  (worker OWNER_DATABASE_URL has postgres:postgres — that's the DB owner cred, still default)"
kubectl -n "$NS" get secret app-secrets -o jsonpath='{.data.POSTGRES_PASSWORD}' 2>/dev/null | base64 -d 2>/dev/null | head -c 40 | (grep -q '^postgres$' && echo "  POSTGRES_PASSWORD = DEFAULT (postgres)" || echo "  POSTGRES_PASSWORD = non-default")
echo DONE
