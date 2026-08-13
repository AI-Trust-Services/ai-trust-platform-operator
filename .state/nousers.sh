#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
PGPOD=$(kubectl -n "$NS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep -E '^postgres' | awk '{print $1}' | head -1)
run(){ kubectl -n "$NS" exec "$PGPOD" -- sh -lc "PGPASSWORD=\$POSTGRES_PASSWORD psql -tA -U \$POSTGRES_USER -d ai_trust -c \"$1\"" 2>&1 | grep -avi memcache; }
echo "=== is there ANY users table in the app DB? ==="
run "SELECT tablename FROM pg_tables WHERE schemaname='public' AND (tablename ILIKE '%user%' OR tablename ILIKE '%account%' OR tablename ILIKE '%member%' OR tablename ILIKE '%identity%');"
echo "(empty above = NO user/account/identity table in Postgres)"
echo
echo "=== ALL tables in the app DB (proof: no user store) ==="
run "SELECT tablename FROM pg_tables WHERE schemaname='public' ORDER BY 1;"
echo
echo "=== where identity/roles actually live: mesh Keycloak (users) + mesh OpenFGA (role tuples) ==="
echo "-- mesh OpenFGA store ai-trust-mt: user->role tuples (this is the closest thing to a 'user list') --"
STOREID=$(kubectl -n "$NS" get deploy ai-system-registry-backend -o jsonpath='{range .spec.template.spec.containers[0].env[?(@.name=="OPENFGA_STORE_ID")]}{.value}{end}' 2>/dev/null | grep -avi memcache)
kubectl -n "$NS" run fga-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet --command -- \
  sh -c "curl -s -X POST http://openfga.platform-mesh-system.svc.cluster.local:8080/stores/$STOREID/read -H 'content-type: application/json' -d '{}'" 2>&1 | grep -avi memcache | tr '}' '\n' | grep -iE '"user":"user:' | head
echo DONE
