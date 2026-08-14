#!/bin/bash
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
f(){ grep -avi memcache; }
PGPOD=$(kubectl -n "$NS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep -E '^postgres' | awk '{print $1}' | head -1)
# As owner: create restricted per-tenant roles, grant each ONLY its schema, revoke ai_trust_app's cross usage,
# make ai_trust_app a member of both. Then test SET ROLE isolation.
kubectl -n "$NS" exec "$PGPOD" -- sh -lc 'PGPASSWORD=$POSTGRES_PASSWORD psql -U $POSTGRES_USER -d $POSTGRES_DB -v ON_ERROR_STOP=1 <<SQL 2>&1
-- restricted roles (NOLOGIN), one per tenant, each only its own schema
DO \$\$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='"'"'t_mirceatest'"'"') THEN CREATE ROLE t_mirceatest NOLOGIN; END IF;
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='"'"'t_sohan'"'"') THEN CREATE ROLE t_sohan NOLOGIN; END IF;
END \$\$;
-- t_mirceatest: only tenant_mirceatest
GRANT USAGE ON SCHEMA tenant_mirceatest TO t_mirceatest;
GRANT SELECT,INSERT,UPDATE,DELETE ON ALL TABLES IN SCHEMA tenant_mirceatest TO t_mirceatest;
-- t_sohan: only tenant_sohan
GRANT USAGE ON SCHEMA tenant_sohan TO t_sohan;
GRANT SELECT,INSERT,UPDATE,DELETE ON ALL TABLES IN SCHEMA tenant_sohan TO t_sohan;
-- app login role can assume either (membership) but should NOT itself have direct cross usage
GRANT t_mirceatest TO ai_trust_app;
GRANT t_sohan TO ai_trust_app;
-- remove the blanket usage ai_trust_app currently has on the tenant schemas (the leak source)
REVOKE ALL ON SCHEMA tenant_mirceatest FROM ai_trust_app;
REVOKE ALL ON SCHEMA tenant_sohan FROM ai_trust_app;
SQL' 2>&1 | f

echo "=== TEST: as ai_trust_app, SET ROLE t_mirceatest, try own vs cross ==="
kubectl -n "$NS" exec "$PGPOD" -- sh -lc 'PGPASSWORD=$POSTGRES_PASSWORD psql -U $POSTGRES_USER -d $POSTGRES_DB <<SQL 2>&1
SET ROLE ai_trust_app;
SET ROLE t_mirceatest;
SELECT '"'"'OWN tenant_mirceatest (ok)'"'"'; SELECT count(*) FROM tenant_mirceatest.ai_systems;
SELECT '"'"'CROSS tenant_sohan (expect permission denied)'"'"'; SELECT count(*) FROM tenant_sohan.ai_systems;
SQL' 2>&1 | f
echo DONE
