#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
BACKENDS="ai-system-registry-backend monitoring-backend overview-backend alerts-backend compliance-backend decision-trace-analyzer-backend users-backend shell policy-checker-worker"
echo "=== give policy-checker-worker OWNER_DATABASE_URL (owner role, for tenant enumeration) ==="
kubectl -n "$NS" set env deploy/policy-checker-worker OWNER_DATABASE_URL="$(kubectl -n "$NS" get secret app-secrets -o jsonpath='{.data.DATABASE_URL}' | base64 -d)" 2>&1 | grep -avi memcache
echo "=== ensure imagePullPolicy Always so the new :aitrust-mt tag is pulled, then restart ==="
for d in $BACKENDS; do
  kubectl -n "$NS" patch deploy "$d" --type=json -p '[{"op":"replace","path":"/spec/template/spec/containers/0/imagePullPolicy","value":"Always"}]' >/dev/null 2>&1
  kubectl -n "$NS" rollout restart deploy/"$d" >/dev/null 2>&1 && echo "  restarted $d"
done
echo "=== wait for rollouts ==="
for d in $BACKENDS; do
  kubectl -n "$NS" rollout status deploy/"$d" --timeout=150s 2>&1 | grep -avi memcache | tail -1
done
echo DONE
