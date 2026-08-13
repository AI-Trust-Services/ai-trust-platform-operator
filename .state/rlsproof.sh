#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
PGPOD=$(kubectl -n "$NS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep -E '^postgres' | awk '{print $1}' | head -1)
# Run as the RLS-bound app role (ai_trust_app), NOT postgres — that's what backends use.
appsql(){ kubectl -n "$NS" exec "$PGPOD" -- sh -lc "PGPASSWORD=apppw psql -U ai_trust_app -d \$POSTGRES_DB -tA -c \"$1\"" 2>&1 | grep -avi memcache; }
ownersql(){ kubectl -n "$NS" exec "$PGPOD" -- sh -lc "PGPASSWORD=\$POSTGRES_PASSWORD psql -U \$POSTGRES_USER -d \$POSTGRES_DB -tA -c \"$1\"" 2>&1 | grep -avi memcache; }

echo "=== APP role reachable? ==="
appsql "SELECT current_user;"

echo "=== seed 2 tenants as owner (idempotent) ==="
ownersql "INSERT INTO ai_systems (id,name,tier,tenant_id) VALUES ('SYS-TENA','sysA','minimal','tenantA') ON CONFLICT (id) DO UPDATE SET tenant_id='tenantA';"
ownersql "INSERT INTO ai_systems (id,name,tier,tenant_id) VALUES ('SYS-TENB','sysB','minimal','tenantB') ON CONFLICT (id) DO UPDATE SET tenant_id='tenantB';"

echo "=== as ai_trust_app, tenantA sees only A (+NULL) ==="
appsql "SET app.current_tenant='tenantA'; SELECT id||':'||COALESCE(tenant_id,'NULL') FROM ai_systems WHERE id IN ('SYS-TENA','SYS-TENB');"
echo "=== tenantB sees only B ==="
appsql "SET app.current_tenant='tenantB'; SELECT id||':'||COALESCE(tenant_id,'NULL') FROM ai_systems WHERE id IN ('SYS-TENA','SYS-TENB');"
echo "=== no tenant set → sees neither scoped row (only NULL rows) ==="
appsql "SELECT id||':'||COALESCE(tenant_id,'NULL') FROM ai_systems WHERE id IN ('SYS-TENA','SYS-TENB');"
echo "=== INSERT stamp: as tenantA, insert with NO tenant_id → auto-stamped tenantA ==="
appsql "SET app.current_tenant='tenantA'; INSERT INTO ai_systems (id,name,tier) VALUES ('SYS-TENC','sysC','minimal');"
appsql "SET app.current_tenant='tenantA'; SELECT id||':'||COALESCE(tenant_id,'NULL') FROM ai_systems WHERE id='SYS-TENC';"
echo "=== cross-tenant write blocked? tenantB tries to write a tenantA row (expect WITH CHECK violation) ==="
appsql "SET app.current_tenant='tenantB'; INSERT INTO ai_systems (id,name,tier,tenant_id) VALUES ('SYS-TEND','sysD','minimal','tenantA');"
echo "=== cleanup ==="
ownersql "DELETE FROM ai_systems WHERE id IN ('SYS-TENA','SYS-TENB','SYS-TENC','SYS-TEND');"
echo DONE
