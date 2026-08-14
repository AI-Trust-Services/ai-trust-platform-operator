#!/bin/bash
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh 2>/dev/null; load_config 2>/dev/null
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
f(){ grep -avi memcache; }

echo "===== A) operator log for org=fridaytest (seeding / tuple / admin / provision) ====="
kubectl -n "$NS" logs deploy/aitrust-mt-operator --tail=1000 2>&1 | f | grep -iE 'fridaytest' | grep -iE 'tuple|admin|seed|openfga|provision|realm|ready|oauth|client' | tail -40
echo "--- any tuple/openfga/seed lines at all (last 20) ---"
kubectl -n "$NS" logs deploy/aitrust-mt-operator --tail=1000 2>&1 | f | grep -iE 'tuple|openfga|seed|admin tuple' | tail -20

echo; echo "===== B) kc-client-fridaytest Job log (client/mapper created; NO secret values) ====="
kubectl -n "$NS" logs job/kc-client-fridaytest --tail=80 2>&1 | f | grep -ivE 'secret|password|client-secret|BEGIN|token=' | tail -60

echo; echo "===== C) oauth2-proxy-fridaytest args (issuer/realm/client-id/scope; no secrets) ====="
kubectl -n "$NS" get deploy oauth2-proxy-fridaytest -o jsonpath='{range .spec.template.spec.containers[0].args[*]}{@}{"\n"}{end}' 2>&1 | f | grep -iE 'oidc|issuer|client-id|redirect|email|scope|cookie|whitelist|upstream|pass-'

echo; echo "===== D) users-backend recent logs (permissions / me / tenant / denied) ====="
kubectl -n "$NS" logs deploy/users-backend --tail=150 2>&1 | f | grep -iE 'permission|/me|tenant|openfga|forbidden|denied|403|401|fridaytest' | tail -30

echo; echo "===== E) users-backend env: tenant + openfga wiring (names only, values are non-secret config) ====="
kubectl -n "$NS" get deploy users-backend -o jsonpath='{range .spec.template.spec.containers[0].env[*]}{.name}={.value}{"\n"}{end}' 2>&1 | f | grep -iE 'TENAN|OPENFGA|FGA|CLAIM|JWKS|ISSUER|MODE'
echo DONE
