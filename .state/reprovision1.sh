#!/bin/bash
# Clean reprovision of the ai_trust DB so its schema/alembic history exactly matches git (0001->0009).
# Safe: all tenant business tables are empty; only catalog seed data (frameworks/model_cards/alert_rules)
# is recreated by the app's seeders. Does NOT touch keycloak DB, mesh Keycloak, OpenFGA, MinIO, ClickHouse.
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
PGPOD=$(kubectl -n "$NS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep -E '^postgres' | awk '{print $1}' | head -1)
echo "pg pod: $PGPOD"
admin(){ kubectl -n "$NS" exec "$PGPOD" -- sh -lc "PGPASSWORD=\$POSTGRES_PASSWORD psql -v ON_ERROR_STOP=1 -U \$POSTGRES_USER -d postgres -c \"$1\"" 2>&1 | grep -avi memcache; }

echo "=== 0. safety snapshot: confirm business tables empty BEFORE drop ==="
kubectl -n "$NS" exec "$PGPOD" -- sh -lc 'PGPASSWORD=$POSTGRES_PASSWORD psql -U $POSTGRES_USER -d ai_trust -tA -c "SELECT '\''ai_systems=\''||count(*) FROM ai_systems; SELECT '\''evidence=\''||count(*) FROM evidence; SELECT '\''assessments=\''||count(*) FROM assessments;"' 2>&1 | grep -avi memcache

echo "=== 1. terminate connections to ai_trust, drop + recreate (owner=postgres) ==="
admin "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='ai_trust' AND pid<>pg_backend_pid();"
admin "DROP DATABASE ai_trust;"
admin "CREATE DATABASE ai_trust;"
echo "=== 2. re-apply the app-role grants baseline on the fresh DB (ALTER DEFAULT PRIVILEGES BEFORE migrate) ==="
kubectl -n "$NS" exec "$PGPOD" -- sh -lc 'PGPASSWORD=$POSTGRES_PASSWORD psql -v ON_ERROR_STOP=1 -U $POSTGRES_USER -d ai_trust <<SQL
GRANT CONNECT ON DATABASE ai_trust TO ai_trust_app;
GRANT USAGE ON SCHEMA public TO ai_trust_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO ai_trust_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO ai_trust_app;
SQL' 2>&1 | grep -avi memcache
echo "reprovision-prep DONE"
