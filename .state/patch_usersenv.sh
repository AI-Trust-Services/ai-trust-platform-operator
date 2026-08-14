#!/bin/bash
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh 2>/dev/null; load_config 2>/dev/null
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
f(){ grep -avi memcache; }

echo "===== confirm mesh-keycloak-admin secret exists in $NS ====="
kubectl -n "$NS" get secret mesh-keycloak-admin >/dev/null 2>&1 && echo "  secret present: yes" || { echo "  secret MISSING — aborting"; exit 1; }

echo; echo "===== add MESH_KC_ADMIN_USER/PASSWORD (only if not already present) ====="
HAS=$(kubectl -n "$NS" get deploy users-backend -o jsonpath='{range .spec.template.spec.containers[0].env[*]}{.name}{"\n"}{end}' 2>/dev/null | grep -c MESH_KC_ADMIN_USER || true)
if [ "$HAS" -eq 0 ]; then
  kubectl -n "$NS" patch deploy/users-backend --type=json -p '[
    {"op":"add","path":"/spec/template/spec/containers/0/env/-","value":{"name":"MESH_KC_ADMIN_USER","valueFrom":{"secretKeyRef":{"name":"mesh-keycloak-admin","key":"username"}}}},
    {"op":"add","path":"/spec/template/spec/containers/0/env/-","value":{"name":"MESH_KC_ADMIN_PASSWORD","valueFrom":{"secretKeyRef":{"name":"mesh-keycloak-admin","key":"password"}}}}
  ]' 2>&1 | f
else
  echo "  already present — skipping patch"
fi

echo; echo "===== rollout + verify ====="
kubectl -n "$NS" rollout status deploy/users-backend --timeout=150s 2>&1 | f | tail -1
echo "  env now:"
kubectl -n "$NS" get deploy users-backend -o jsonpath='{range .spec.template.spec.containers[0].env[*]}{.name}{"\n"}{end}' 2>&1 | f | grep -iE 'TENANCY_MODE|MESH_KC_ADMIN|KEYCLOAK_URL|KEYCLOAK_REALM' | sed 's/^/    /'
echo DONE
