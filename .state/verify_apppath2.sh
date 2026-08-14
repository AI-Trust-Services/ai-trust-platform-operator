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
echo "=== real columns of tenant_sohan.ai_systems ==="
kubectl -n "$NS" exec "$PGPOD" -- sh -lc 'PGPASSWORD=$POSTGRES_PASSWORD psql -U $POSTGRES_USER -d $POSTGRES_DB -tAc "SELECT string_agg(column_name,'"'"', '"'"') FROM information_schema.columns WHERE table_schema='"'"'tenant_sohan'"'"' AND table_name='"'"'ai_systems'"'"' AND is_nullable='"'"'NO'"'"'"' 2>&1 | f
echo; echo "=== APP-PATH: SET LOCAL ROLE t_sohan, insert a minimal row, read it back, then ROLLBACK ==="
kubectl -n "$NS" exec "$PGPOD" -- sh -lc "PGPASSWORD='$APPPW' psql -h localhost -U ai_trust_app -d \$POSTGRES_DB <<SQL 2>&1
BEGIN;
SELECT set_config('search_path','\"tenant_sohan\",public',true), set_config('app.current_tenant','sohan',true);
SET LOCAL ROLE t_sohan;
INSERT INTO ai_systems (id, name, tier, lifecycle) VALUES ('SYS-HWTEST1','hardwall probe','minimal','development');
SELECT 'own-tenant write+read ok:', count(*) FROM ai_systems WHERE id='SYS-HWTEST1';
SELECT 'tenant_id stamped by RLS default:', tenant_id FROM ai_systems WHERE id='SYS-HWTEST1';
ROLLBACK;
SQL" 2>&1 | f
echo DONE
