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

echo "=== APP-PATH SIM: as ai_trust_app, replicate session hook (SET LOCAL ROLE + search_path + tenant), write+read in tenant_sohan ==="
kubectl -n "$NS" exec "$PGPOD" -- sh -lc "PGPASSWORD='$APPPW' psql -h localhost -U ai_trust_app -d \$POSTGRES_DB <<SQL 2>&1
BEGIN;
SELECT set_config('search_path','\"tenant_sohan\",public',true), set_config('app.current_tenant','sohan',true);
SET LOCAL ROLE t_sohan;
INSERT INTO ai_systems (id, name, tier, lifecycle, purpose) VALUES ('SYS-HWTEST1','hardwall probe','minimal','development','isolation test');
SELECT 'inserted+read in own tenant:', count(*) FROM ai_systems WHERE id='SYS-HWTEST1';
SELECT 'cross tenant_livedemo (expect DENIED):';
SELECT count(*) FROM tenant_livedemo.ai_systems;
ROLLBACK;
SQL" 2>&1 | f
echo "  (insert+read should work; cross should ERROR; ROLLBACK leaves no trace)"

echo; echo "=== real backend health (DB connectivity with NOINHERIT app role) ==="
for b in users-backend compliance-backend overview-backend; do
  P=$(kubectl -n "$NS" get pods -l app=$b --no-headers 2>/dev/null | grep -avi memcache | grep -c Running || true)
  echo "  $b running pods: $P"
done
kubectl -n "$NS" logs deploy/users-backend --tail=20 2>&1 | f | grep -iE '/health.*200|error|500|permission denied' | tail -3
echo DONE
