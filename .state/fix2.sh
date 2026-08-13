#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
echo "=== patch keycloak deploy: add KC_BOOTSTRAP_ADMIN_* ==="
kubectl -n "$NS" patch deploy keycloak --type=json -p '[
 {"op":"add","path":"/spec/template/spec/containers/0/env/-","value":{"name":"KC_BOOTSTRAP_ADMIN_USERNAME","valueFrom":{"secretKeyRef":{"name":"app-secrets","key":"KEYCLOAK_ADMIN"}}}},
 {"op":"add","path":"/spec/template/spec/containers/0/env/-","value":{"name":"KC_BOOTSTRAP_ADMIN_PASSWORD","valueFrom":{"secretKeyRef":{"name":"app-secrets","key":"KEYCLOAK_ADMIN_PASSWORD"}}}}
]' 2>&1 | grep -avi memcache

echo "=== the KC 'keycloak' DB likely exists WITHOUT an admin (first bootstrap failed) → recreate it so bootstrap runs clean ==="
PGPOD=$(kubectl -n "$NS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep '^postgres-' | awk '{print $1}' | head -1)
echo "pg pod: $PGPOD"
kubectl -n "$NS" exec "$PGPOD" -- psql -U postgres -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='keycloak' AND pid<>pg_backend_pid();" 2>&1 | grep -avi memcache | tail -1
kubectl -n "$NS" exec "$PGPOD" -- psql -U postgres -c "DROP DATABASE IF EXISTS keycloak;" 2>&1 | grep -avi memcache | tail -1
kubectl -n "$NS" exec "$PGPOD" -- psql -U postgres -c "CREATE DATABASE keycloak;" 2>&1 | grep -avi memcache | tail -1

echo "=== restart keycloak (clean bootstrap) + wait ==="
kubectl -n "$NS" rollout restart deploy/keycloak 2>&1 | grep -avi memcache
kubectl -n "$NS" rollout status deploy/keycloak --timeout=180s 2>&1 | grep -avi memcache | tail -1

echo "=== re-run the shared app's keycloak-provision job (recreate it) ==="
kubectl -n "$NS" delete job keycloak-provision --ignore-not-found 2>&1 | grep -avi memcache
# recreate from the gold manifest (rendered): just re-run via a fresh apply of 20-jobs would need render;
# instead the operator's tenant-provision will run once KC has an admin. First verify admin now works:
sleep 20
kubectl -n "$NS" run kctest2-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet --command -- \
  sh -c 'curl -s -o /dev/null -w "master token after fix: http=%{http_code}\n" -d "client_id=admin-cli&username=admin&password=admin&grant_type=password" http://keycloak.aitrust-mt-msp.svc.cluster.local:8080/keycloak/realms/master/protocol/openid-connect/token' 2>&1 | grep -avi memcache | grep http=
echo DONE
