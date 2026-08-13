#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
PGPOD=$(kubectl -n "$NS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep -E '^postgres' | awk '{print $1}' | head -1)
CLIENTS="ai-system-registry-backend monitoring-backend overview-backend alerts-backend compliance-backend decision-trace-analyzer-backend users-backend policy-checker-worker otel-clickhouse-consumer otel-rmq-bridge"

echo "=== reconcile grants on the freshly-migrated tables (belt-and-suspenders) ==="
kubectl -n "$NS" exec "$PGPOD" -- sh -lc 'PGPASSWORD=$POSTGRES_PASSWORD psql -v ON_ERROR_STOP=1 -U $POSTGRES_USER -d ai_trust <<SQL
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO ai_trust_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO ai_trust_app;
SQL' 2>&1 | grep -avi memcache | tail -3

echo "=== scale clients back up ==="
for d in $CLIENTS; do kubectl -n "$NS" scale deploy/$d --replicas=1 >/dev/null 2>&1 && echo "  up $d"; done

echo "=== verify: alembic version, table count, seed rows, grants ==="
run(){ kubectl -n "$NS" exec "$PGPOD" -- sh -lc "PGPASSWORD=\$POSTGRES_PASSWORD psql -tA -U \$POSTGRES_USER -d ai_trust -c \"$1\"" 2>&1 | grep -avi memcache; }
echo "  alembic: $(run 'SELECT version_num FROM alembic_version;')"
echo "  tables:  $(run "SELECT count(*) FROM pg_tables WHERE schemaname='public';")"
echo "  frameworks=$(run 'SELECT count(*) FROM frameworks;') model_cards=$(run 'SELECT count(*) FROM model_cards;') alert_rules=$(run 'SELECT count(*) FROM alert_rules;') custom_roles=$(run 'SELECT count(*) FROM custom_roles;')"
echo "  tables missing ai_trust_app SELECT grant: $(run "SELECT count(*) FROM pg_tables t WHERE t.schemaname='public' AND NOT EXISTS (SELECT 1 FROM information_schema.role_table_grants g WHERE g.table_name=t.tablename AND g.grantee='ai_trust_app' AND g.privilege_type='SELECT');")"
echo "  RLS tables: $(run "SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relrowsecurity;")"
echo DONE
