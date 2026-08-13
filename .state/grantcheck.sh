#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
PGPOD=$(kubectl -n "$NS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep -E '^postgres' | awk '{print $1}' | head -1)
run(){ kubectl -n "$NS" exec "$PGPOD" -- sh -lc "PGPASSWORD=\$POSTGRES_PASSWORD psql -U \$POSTGRES_USER -d \$POSTGRES_DB -tA -c \"$1\"" 2>&1 | grep -avi memcache; }
echo "=== ai_trust_app grants on ai_systems (reference for what custom_roles needs) ==="
run "SELECT grantee||':'||privilege_type FROM information_schema.role_table_grants WHERE table_name='ai_systems' AND grantee='ai_trust_app';"
echo "=== is ai_trust_app maybe a member of a role that owns tables, or does pg-init GRANT ALL? ==="
run "SELECT r.rolname FROM pg_auth_members m JOIN pg_roles r ON r.oid=m.roleid JOIN pg_roles u ON u.oid=m.member WHERE u.rolname='ai_trust_app';"
echo DONE
