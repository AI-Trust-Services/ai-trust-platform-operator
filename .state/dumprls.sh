#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
PGPOD=$(kubectl -n "$NS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep -E '^postgres' | awk '{print $1}' | head -1)
echo "pg pod: $PGPOD"
run(){ kubectl -n "$NS" exec "$PGPOD" -- sh -lc "PGPASSWORD=\$POSTGRES_PASSWORD psql -U \$POSTGRES_USER -d \$POSTGRES_DB -tA -c \"$1\"" 2>&1 | grep -avi memcache; }

echo "=== 1. ALL tables with RLS enabled (relforcerowsecurity too) ==="
run "SELECT c.relname||' rls='||c.relrowsecurity||' force='||c.relforcerowsecurity FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relkind='r' AND c.relrowsecurity ORDER BY 1;"

echo "=== 2. FULL policy defs (name, cmd, USING qual, WITH CHECK) ==="
run "SELECT tablename||' | '||policyname||' | cmd='||cmd||' | using='||COALESCE(qual,'-')||' | check='||COALESCE(with_check,'-') FROM pg_policies WHERE schemaname='public' ORDER BY tablename;"

echo "=== 3. tenant_id columns: table, nullable, default ==="
run "SELECT table_name||' | null='||is_nullable||' | default='||COALESCE(column_default,'-')||' | type='||data_type FROM information_schema.columns WHERE table_schema='public' AND column_name='tenant_id' ORDER BY table_name;"

echo "=== 4. alembic version currently stamped ==="
run "SELECT version_num FROM alembic_version;"

echo "=== 5. ai_trust_app role attrs (bypassrls?) ==="
run "SELECT rolname||' super='||rolsuper||' bypassrls='||rolbypassrls FROM pg_roles WHERE rolname IN ('ai_trust_app','postgres');"
echo DONE
