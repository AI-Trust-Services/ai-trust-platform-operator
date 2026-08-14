#!/bin/bash
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh 2>/dev/null; load_config 2>/dev/null
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
f(){ grep -avi memcache; }

echo "===== oauth2-proxy-fridaytest logs: logout / sign_out / error (recent) ====="
kubectl -n "$NS" logs deploy/oauth2-proxy-fridaytest --tail=60 2>&1 | f | grep -iE 'sign_out|logout|error|session|redirect' | tail -20

echo; echo "===== which backends are up? (all deployments ready?) ====="
kubectl -n "$NS" get deploy --no-headers 2>&1 | f | awk '{print $1, $2}' | grep -iE 'backend|shell'

echo; echo "===== any backend NOT 1/1? ====="
kubectl -n "$NS" get pods --no-headers 2>&1 | f | grep -ivE '1/1|Completed' | grep -iE 'backend|shell|proxy' || echo "  (all backends 1/1)"

echo; echo "===== users-backend + overview-backend recent errors (the banner polls health) ====="
for b in users-backend overview-backend alerts-backend; do
  echo "--- $b (last 5, non-200 or error) ---"
  kubectl -n "$NS" logs deploy/$b --tail=40 2>&1 | f | grep -iE 'error|500|503|degraded|traceback|tenant|exception' | tail -5 || echo "  (clean)"
done
echo DONE
