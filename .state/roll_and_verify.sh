#!/bin/bash
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh 2>/dev/null; load_config 2>/dev/null
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
f(){ grep -avi memcache; }

# App deployments to roll (NOT the operator/oauth2-proxies — those aren't rebuilt).
DEPLOYS="users-frontend users-backend shell ai-system-registry-backend alerts-backend compliance-backend compliance-frontend decision-trace-analyzer-backend monitoring-backend overview-backend aitrust-mt-portal-integration"

echo "===== ensure imagePullPolicy=Always so :aitrust-mt is re-pulled (not cached) ====="
for d in $DEPLOYS; do
  kubectl -n "$NS" patch deploy "$d" --type=json \
    -p '[{"op":"replace","path":"/spec/template/spec/containers/0/imagePullPolicy","value":"Always"}]' 2>&1 | f | sed "s/^/  $d: /" || true
done

echo; echo "===== rollout restart all app deployments ====="
for d in $DEPLOYS; do kubectl -n "$NS" rollout restart deploy/"$d" 2>&1 | f; done

echo; echo "===== wait for readiness ====="
for d in $DEPLOYS; do kubectl -n "$NS" rollout status deploy/"$d" --timeout=180s 2>&1 | f | tail -1; done

echo; echo "===== VERIFY: users-frontend bundle now contains /api/users/v1 (the fix) ====="
sleep 3
kubectl -n "$NS" exec deploy/users-frontend -- sh -c 'grep -rhoE "api/users/v1|Missing required environment variable" /usr/share/nginx/html/assets/*.js 2>/dev/null | sort -u | head' 2>&1 | f
echo "  (expect: api/users/v1  present, and NO 'Missing required environment variable')"
echo DONE
