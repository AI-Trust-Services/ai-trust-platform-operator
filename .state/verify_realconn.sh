#!/bin/bash
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
f(){ grep -avi memcache; }
PGPOD=$(kubectl -n "$NS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep -E '^postgres' | awk '{print $1}' | head -1)
# Connect AS ai_trust_app directly (real runtime identity), using APP_DATABASE_URL creds.
APPPW=$(kubectl -n "$NS" get secret app-secrets -o jsonpath='{.data.APP_DATABASE_URL}' 2>/dev/null | base64 -d | sed -E 's#.*://ai_trust_app:([^@]*)@.*#\1#')
echo "=== connect AS ai_trust_app (real identity). NOINHERIT => no ambient tenant access ==="
kubectl -n "$NS" exec "$PGPOD" -- sh -lc "PGPASSWORD='$APPPW' psql -h localhost -U ai_trust_app -d \$POSTGRES_DB <<SQL 2>&1
SELECT 'A) no SET ROLE, tenant_sohan (expect DENIED):';
SELECT count(*) FROM tenant_sohan.ai_systems;
SET ROLE t_sohan;
SELECT 'B) after SET ROLE t_sohan, own (ok):', count(*) FROM tenant_sohan.ai_systems;
SELECT 'C) SET ROLE t_sohan, cross tenant_mirceatest (expect DENIED):';
SELECT count(*) FROM tenant_mirceatest.ai_systems;
SQL" 2>&1 | f
echo DONE
