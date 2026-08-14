#!/bin/bash
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh 2>/dev/null; load_config 2>/dev/null
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
f(){ grep -avi memcache; }

echo "===== users-backend env: FULL tenancy wiring ====="
kubectl -n "$NS" get deploy users-backend -o jsonpath='{range .spec.template.spec.containers[0].env[*]}{.name}={.value}{"\n"}{end}' 2>&1 | f | grep -iE 'TENANC|TENANT|JWKS|JWT|ISSUER|AUDIENCE|VERIFY|MODE|CLAIM|ALLOW'

echo; echo "===== users-backend logs: last 60, focus on tenancy/jwt/401/decode/issuer/audience ====="
kubectl -n "$NS" logs deploy/users-backend --tail=250 2>&1 | f | grep -iE 'tenanc|jwt|jwk|issuer|audience|decode|401|unauthor|invalid|verify|claim|token|resolver' | tail -40

echo; echo "===== does the MT users-backend actually contain libs/tenancy? (import + middleware) ====="
kubectl -n "$NS" exec deploy/users-backend -- python -c 'import importlib.util as u; print("ai_trust_tenancy:", "FOUND" if u.find_spec("ai_trust_tenancy") else "MISSING")' 2>&1 | f
kubectl -n "$NS" exec deploy/users-backend -- python -c 'import ai_trust_tenancy, os; print("module file:", ai_trust_tenancy.__file__)' 2>&1 | f
echo DONE
