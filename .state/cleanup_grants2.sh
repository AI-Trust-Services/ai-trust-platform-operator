#!/bin/bash
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
f(){ grep -avi memcache; }
PGPOD=$(kubectl -n "$NS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep -E '^postgres' | awk '{print $1}' | head -1)
# Build plain REVOKE statements per known tenant schema (no DO $$).
SQL=""
for s in tenant_livedemo tenant_mirceatest tenant_mttest2 tenant_sohan; do
  SQL="$SQL REVOKE ALL ON ALL TABLES IN SCHEMA $s FROM ai_trust_app; REVOKE ALL ON ALL SEQUENCES IN SCHEMA $s FROM ai_trust_app; REVOKE ALL ON SCHEMA $s FROM ai_trust_app;"
done
echo "=== applying REVOKEs ==="
kubectl -n "$NS" exec "$PGPOD" -- sh -lc "PGPASSWORD=\$POSTGRES_PASSWORD psql -U \$POSTGRES_USER -d \$POSTGRES_DB -c \"$SQL\"" 2>&1 | f

APPURL=$(kubectl -n "$NS" get secret app-secrets -o jsonpath='{.data.APP_DATABASE_URL}' 2>/dev/null | base64 -d)
APPPW=$(echo "$APPURL" | sed -E 's#.*://[^:]*:([^@]*)@.*#\1#')
echo "=== VERIFY A: ai_trust_app, NO set role, tenant_sohan → expect permission denied ==="
kubectl -n "$NS" exec "$PGPOD" -- sh -lc "PGPASSWORD='$APPPW' psql -h localhost -U ai_trust_app -d \$POSTGRES_DB -c 'SELECT id FROM tenant_sohan.ai_systems LIMIT 1'" 2>&1 | f
echo "=== VERIFY B: ai_trust_app + SET ROLE t_sohan → own OK ==="
kubectl -n "$NS" exec "$PGPOD" -- sh -lc "PGPASSWORD='$APPPW' psql -h localhost -U ai_trust_app -d \$POSTGRES_DB -c 'SET ROLE t_sohan; SELECT count(*) FROM tenant_sohan.ai_systems'" 2>&1 | f
echo "=== VERIFY C: ai_trust_app + SET ROLE t_sohan → cross tenant_mirceatest → expect denied ==="
kubectl -n "$NS" exec "$PGPOD" -- sh -lc "PGPASSWORD='$APPPW' psql -h localhost -U ai_trust_app -d \$POSTGRES_DB -c 'SET ROLE t_sohan; SELECT count(*) FROM tenant_mirceatest.ai_systems'" 2>&1 | f
echo "=== table ACL now (ai_trust_app should be GONE) ==="
kubectl -n "$NS" exec "$PGPOD" -- sh -lc 'PGPASSWORD=$POSTGRES_PASSWORD psql -U $POSTGRES_USER -d $POSTGRES_DB -tAc "SELECT relacl FROM pg_class WHERE relname='"'"'ai_systems'"'"' AND relnamespace=(SELECT oid FROM pg_namespace WHERE nspname='"'"'tenant_sohan'"'"')"' 2>&1 | f
echo DONE
