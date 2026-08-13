#!/bin/bash
# Clean reprovision, done safely: scale down all DB clients so nothing reconnects during DROP.
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
PGPOD=$(kubectl -n "$NS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep -E '^postgres' | awk '{print $1}' | head -1)
CLIENTS="ai-system-registry-backend monitoring-backend overview-backend alerts-backend compliance-backend decision-trace-analyzer-backend users-backend policy-checker-worker otel-clickhouse-consumer otel-rmq-bridge"

echo "=== 1. scale down all DB clients (record replicas) ==="
for d in $CLIENTS; do kubectl -n "$NS" scale deploy/$d --replicas=0 >/dev/null 2>&1 && echo "  down $d"; done
echo "  waiting for connections to drain…"; sleep 12

echo "=== 2. drop + recreate ai_trust (no clients now) ==="
kubectl -n "$NS" exec "$PGPOD" -- sh -lc 'PGPASSWORD=$POSTGRES_PASSWORD psql -v ON_ERROR_STOP=1 -U $POSTGRES_USER -d postgres <<SQL
SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='"'"'ai_trust'"'"' AND pid<>pg_backend_pid();
DROP DATABASE IF EXISTS ai_trust;
CREATE DATABASE ai_trust;
SQL' 2>&1 | grep -avi memcache | tail -4

echo "=== 3. grant baseline (ALTER DEFAULT PRIVILEGES before migrate so all new tables auto-grant) ==="
kubectl -n "$NS" exec "$PGPOD" -- sh -lc 'PGPASSWORD=$POSTGRES_PASSWORD psql -v ON_ERROR_STOP=1 -U $POSTGRES_USER -d ai_trust <<SQL
GRANT CONNECT ON DATABASE ai_trust TO ai_trust_app;
GRANT USAGE ON SCHEMA public TO ai_trust_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO ai_trust_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO ai_trust_app;
SQL' 2>&1 | grep -avi memcache | tail -4
echo "PREP_DONE (DB dropped+recreated empty, default privileges set)"
