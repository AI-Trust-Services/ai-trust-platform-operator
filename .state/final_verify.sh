#!/bin/bash
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh 2>/dev/null; load_config 2>/dev/null
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
f(){ grep -avi memcache; }

echo "===== operator image (expect v9) ====="
kubectl -n "$NS" get deploy aitrust-mt-operator -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}' 2>&1 | f

echo; echo "===== users-backend: image + tenancy env + health ====="
kubectl -n "$NS" get deploy users-backend -o jsonpath='image={.spec.template.spec.containers[0].image}{"\n"}' 2>&1 | f
kubectl -n "$NS" get deploy users-backend -o jsonpath='{range .spec.template.spec.containers[0].env[*]}{.name}{" "}{end}{"\n"}' 2>&1 | f | tr " " "\n" | grep -iE 'TENANCY_MODE|MESH_KC_ADMIN|KEYCLOAK_URL' | sed 's/^/  /'
kubectl -n "$NS" get pods -l app=users-backend --no-headers 2>&1 | f

echo; echo "===== all oauth2-proxy-<org> have id_token_hint in backend-logout-url ====="
for d in $(kubectl -n "$NS" get deploy -o name 2>/dev/null | grep -avi memcache | grep oauth2-proxy); do
  ORG=$(echo "$d" | sed 's#.*/oauth2-proxy-##')
  L=$(kubectl -n "$NS" get "$d" -o jsonpath='{range .spec.template.spec.containers[0].args[*]}{@}{"\n"}{end}' 2>/dev/null | grep -avi memcache | grep -i backend-logout)
  echo "$L" | grep -q 'id_token_hint' && echo "  $ORG: OK (id_token_hint present)" || echo "  $ORG: MISSING id_token_hint"
done
echo DONE
