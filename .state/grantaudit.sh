#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
PGPOD=$(kubectl -n "$NS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep -E '^postgres' | awk '{print $1}' | head -1)
run(){ kubectl -n "$NS" exec "$PGPOD" -- sh -lc "PGPASSWORD=\$POSTGRES_PASSWORD psql -U \$POSTGRES_USER -d \$POSTGRES_DB -tA -c \"$1\"" 2>&1 | grep -avi memcache; }
echo "=== does ai_trust_app now have grants on custom_roles? (my manual grant) ==="
run "SELECT privilege_type FROM information_schema.role_table_grants WHERE table_name='custom_roles' AND grantee='ai_trust_app' ORDER BY 1;"
echo "=== ALL public tables missing an ai_trust_app SELECT grant (would 500 for the app) ==="
run "SELECT t.tablename FROM pg_tables t WHERE t.schemaname='public' AND NOT EXISTS (SELECT 1 FROM information_schema.role_table_grants g WHERE g.table_name=t.tablename AND g.grantee='ai_trust_app' AND g.privilege_type='SELECT') ORDER BY 1;"
echo "(empty above = every table is granted — good)"
echo "=== is ALTER DEFAULT PRIVILEGES active for future tables? ==="
run "SELECT count(*) AS defacl_rules FROM pg_default_acl;"
echo DONE
