#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
echo "=== roll operator to v2 + fix KC_URL env (append /keycloak) ==="
kubectl -n "$NS" set image deploy/aitrust-mt-operator '*'=mirceacraciun795/aitrust-mt-operator:v2 2>&1 | grep -avi memcache
kubectl -n "$NS" set env deploy/aitrust-mt-operator KC_URL="http://keycloak.$NS.svc.cluster.local:8080/keycloak" 2>&1 | grep -avi memcache
kubectl -n "$NS" rollout status deploy/aitrust-mt-operator --timeout=90s 2>&1 | grep -avi memcache | tail -1

echo "=== delete the failed tenant-provision job so the operator re-creates it (fixed template) ==="
kubectl -n "$NS" delete job -l tenant --ignore-not-found 2>&1 | grep -avi memcache
kubectl -n "$NS" get jobs 2>&1 | grep -avi memcache | grep prov- || echo "  (prov job cleared)"

echo "=== investigate the shared app's own keycloak-provision 403 ==="
echo "-- is master realm reachable + is the admin bootstrap present? probe from inside the cluster --"
kubectl -n "$NS" run kctest-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet --command -- \
  sh -c 'curl -s -o /dev/null -w "master token endpoint: http=%{http_code}\n" -d "client_id=admin-cli&username=admin&password=admin&grant_type=password" http://keycloak.aitrust-mt-msp.svc.cluster.local:8080/keycloak/realms/master/protocol/openid-connect/token' 2>&1 | grep -avi memcache | grep http=
echo "-- keycloak env: does it use KC_BOOTSTRAP_ADMIN (KC25+) or the legacy KEYCLOAK_ADMIN? --"
kubectl -n "$NS" get deploy keycloak -o jsonpath='{range .spec.template.spec.containers[0].env[*]}{.name}{"\n"}{end}' 2>&1 | grep -avi memcache | grep -iE 'ADMIN|BOOTSTRAP'
echo DONE
