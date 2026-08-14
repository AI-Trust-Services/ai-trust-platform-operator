#!/bin/bash
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
f(){ grep -avi memcache; }
PGPOD=$(kubectl -n "$NS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep -E '^postgres' | awk '{print $1}' | head -1)
echo "=== ensure NOINHERIT + re-grant all t_<org> memberships WITH INHERIT FALSE ==="
SQL="ALTER ROLE ai_trust_app NOINHERIT;"
for r in t_livedemo t_mirceatest t_mttest2 t_sohan; do
  SQL="$SQL GRANT $r TO ai_trust_app WITH INHERIT FALSE;"
done
kubectl -n "$NS" exec "$PGPOD" -- sh -lc "PGPASSWORD=\$POSTGRES_PASSWORD psql -U \$POSTGRES_USER -d \$POSTGRES_DB -c \"$SQL\"" 2>&1 | f
echo "=== inherit_option per membership (all should be f) ==="
kubectl -n "$NS" exec "$PGPOD" -- sh -lc 'PGPASSWORD=$POSTGRES_PASSWORD psql -U $POSTGRES_USER -d $POSTGRES_DB -tAc "SELECT g.rolname, m.inherit_option FROM pg_auth_members m JOIN pg_roles g ON m.roleid=g.oid JOIN pg_roles a ON m.member=a.oid WHERE a.rolname='"'"'ai_trust_app'"'"' AND g.rolname LIKE '"'"'t\_%'"'"' ORDER BY 1"' 2>&1 | f

echo; echo "=== FLEET HARD-WALL TEST as ai_trust_app (real login) ==="
APPURL=$(kubectl -n "$NS" get secret app-secrets -o jsonpath='{.data.APP_DATABASE_URL}' 2>/dev/null | base64 -d)
APPPW=$(echo "$APPURL" | sed -E 's#.*://[^:]*:([^@]*)@.*#\1#')
for t in livedemo mirceatest mttest2 sohan; do
  R=$(kubectl -n "$NS" exec "$PGPOD" -- sh -lc "PGPASSWORD='$APPPW' psql -h localhost -U ai_trust_app -d \$POSTGRES_DB -tAc 'SELECT 1 FROM tenant_$t.ai_systems LIMIT 1' 2>&1" | grep -avi memcache | tr -d '\n')
  echo "  no-set-role tenant_$t : ${R:0:60}"
done
echo "  (all should say: permission denied for schema tenant_<t>)"
echo "=== and SET ROLE t_sohan → own OK, cross → denied ==="
kubectl -n "$NS" exec "$PGPOD" -- sh -lc "PGPASSWORD='$APPPW' psql -h localhost -U ai_trust_app -d \$POSTGRES_DB -c 'SET ROLE t_sohan; SELECT count(*) FROM tenant_sohan.ai_systems'" 2>&1 | f
kubectl -n "$NS" exec "$PGPOD" -- sh -lc "PGPASSWORD='$APPPW' psql -h localhost -U ai_trust_app -d \$POSTGRES_DB -c 'SET ROLE t_sohan; SELECT 1 FROM tenant_livedemo.ai_systems LIMIT 1'" 2>&1 | f
echo DONE
