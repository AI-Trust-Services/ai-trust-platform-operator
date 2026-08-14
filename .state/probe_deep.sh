#!/bin/bash
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
f(){ grep -avi memcache; }
PGPOD=$(kubectl -n "$NS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep -E '^postgres' | awk '{print $1}' | head -1)
APPURL=$(kubectl -n "$NS" get secret app-secrets -o jsonpath='{.data.APP_DATABASE_URL}' 2>/dev/null | base64 -d)
APPPW=$(echo "$APPURL" | sed -E 's#.*://[^:]*:([^@]*)@.*#\1#')
echo "=== table-level ACL on tenant_sohan.ai_systems (does ai_trust_app have direct table grant?) ==="
kubectl -n "$NS" exec "$PGPOD" -- sh -lc 'PGPASSWORD=$POSTGRES_PASSWORD psql -U $POSTGRES_USER -d $POSTGRES_DB -tAc "SELECT relname, relacl FROM pg_class WHERE relname='"'"'ai_systems'"'"' AND relnamespace=(SELECT oid FROM pg_namespace WHERE nspname='"'"'tenant_sohan'"'"')"' 2>&1 | f
echo "=== as ai_trust_app: explicit has_schema_privilege on tenant_sohan (self) ==="
kubectl -n "$NS" exec "$PGPOD" -- sh -lc "PGPASSWORD='$APPPW' psql -h localhost -U ai_trust_app -d \$POSTGRES_DB -tAc \"SELECT has_schema_privilege(current_user,'tenant_sohan','USAGE'), has_table_privilege(current_user,'tenant_sohan.ai_systems','SELECT')\"" 2>&1 | f
echo "=== force a real row-touch: SELECT id FROM ... LIMIT 1 (can't be optimized away) ==="
kubectl -n "$NS" exec "$PGPOD" -- sh -lc "PGPASSWORD='$APPPW' psql -h localhost -U ai_trust_app -d \$POSTGRES_DB -c 'SELECT id FROM tenant_sohan.ai_systems LIMIT 1'" 2>&1 | f
echo DONE
