#!/bin/bash
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh 2>/dev/null; load_config 2>/dev/null
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
f(){ grep -avi memcache; }

echo "===== users-backend recent logs (403 / tenant / jwt / decode / 401) ====="
kubectl -n "$NS" logs deploy/users-backend --tail=60 2>&1 | f | grep -iE '403|401|tenant|jwt|decode|denied|forbidden|error|client_error' | tail -20

echo; echo "===== oauth2-proxy-fridaytest logs (auth errors / secret / oidc) ====="
kubectl -n "$NS" logs deploy/oauth2-proxy-fridaytest --tail=40 2>&1 | f | grep -iE 'error|invalid|secret|denied|401|403|refresh|token|oidc' | tail -20

echo; echo "===== did the re-stamp ROTATE the client secret? compare secret in K8s vs what proxy uses ====="
# the per-org secret aitrust-mt-oauth2-fridaytest holds client-secret; the proxy reads it via CLIENT_SECRET env.
# The kc-client Job PUT the client with \"secret\":\$CLIENT_SECRET from that SAME k8s secret — so they SHOULD match.
# But if the Job regenerated/re-set it, and the proxy pod didn't restart, mismatch is possible.
echo "  oauth2-proxy-fridaytest pod age (restarted after re-stamp?):"
kubectl -n "$NS" get pods -l org=fridaytest --no-headers 2>&1 | f
echo "  aitrust-mt-oauth2-fridaytest secret age:"
kubectl -n "$NS" get secret aitrust-mt-oauth2-fridaytest -o jsonpath='{.metadata.creationTimestamp}{"\n"}' 2>&1 | f
echo DONE
