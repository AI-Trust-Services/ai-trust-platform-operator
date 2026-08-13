#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
PGPOD=$(kubectl -n "$NS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep -E '^postgres' | awk '{print $1}' | head -1)
owner(){ kubectl -n "$NS" exec "$PGPOD" -- sh -lc "PGPASSWORD=\$POSTGRES_PASSWORD psql -U \$POSTGRES_USER -d \$POSTGRES_DB -c \"$1\"" 2>&1 | grep -avi memcache; }
echo "=== create custom_roles (0008 schema, missing from this DB) ==="
owner "CREATE TABLE IF NOT EXISTS custom_roles (id VARCHAR(64) PRIMARY KEY, name VARCHAR(128) NOT NULL UNIQUE, description TEXT, created_at TIMESTAMPTZ NOT NULL DEFAULT now());"
echo "=== grant the runtime app role access (it connects as ai_trust_app) ==="
owner "GRANT SELECT, INSERT, UPDATE, DELETE ON custom_roles TO ai_trust_app;"
echo "=== verify ==="
owner "SELECT count(*) AS custom_roles_rows FROM custom_roles;"
echo DONE
