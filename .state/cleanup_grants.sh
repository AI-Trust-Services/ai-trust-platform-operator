#!/bin/bash
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
f(){ grep -avi memcache; }
PGPOD=$(kubectl -n "$NS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep -E '^postgres' | awk '{print $1}' | head -1)
echo "=== revoke ALL direct grants (schema+tables+sequences) from ai_trust_app on every tenant schema ==="
kubectl -n "$NS" exec "$PGPOD" -- sh -lc 'PGPASSWORD=$POSTGRES_PASSWORD psql -U $POSTGRES_USER -d $POSTGRES_DB <<SQL 2>&1
DO $$
DECLARE s text;
BEGIN
  FOR s IN SELECT nspname FROM pg_namespace WHERE nspname LIKE '"'"'tenant_%'"'"' LOOP
    EXECUTE format('"'"'REVOKE ALL ON ALL TABLES IN SCHEMA %I FROM ai_trust_app'"'"', s);
    EXECUTE format('"'"'REVOKE ALL ON ALL SEQUENCES IN SCHEMA %I FROM ai_trust_app'"'"', s);
    EXECUTE format('"'"'REVOKE ALL ON SCHEMA %I FROM ai_trust_app'"'"', s);
  END LOOP;
END $$;
SQL' 2>&1 | f
echo "=== re-verify: as ai_trust_app WITHOUT set role, tenant_sohan must now be DENIED ==="
APPURL=$(kubectl -n "$NS" get secret app-secrets -o jsonpath='{.data.APP_DATABASE_URL}' 2>/dev/null | base64 -d)
APPPW=$(echo "$APPURL" | sed -E 's#.*://[^:]*:([^@]*)@.*#\1#')
kubectl -n "$NS" exec "$PGPOD" -- sh -lc "PGPASSWORD='$APPPW' psql -h localhost -U ai_trust_app -d \$POSTGRES_DB -c 'SELECT id FROM tenant_sohan.ai_systems LIMIT 1'" 2>&1 | f
echo "--- ^ expect: ERROR permission denied for schema tenant_sohan ---"
echo "=== and WITH set role t_sohan → own works ==="
kubectl -n "$NS" exec "$PGPOD" -- sh -lc "PGPASSWORD='$APPPW' psql -h localhost -U ai_trust_app -d \$POSTGRES_DB -c 'SET ROLE t_sohan; SELECT count(*) FROM tenant_sohan.ai_systems'" 2>&1 | f
echo DONE
