#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
# is the current shoot kubeconfig still valid?
if ! kubectl -n "$NS" get deploy ai-system-registry-backend >/dev/null 2>&1; then
  echo "SHOOT_KUBECONFIG_EXPIRED"; exit 7
fi
echo "=== roll backends + worker to AC4 image ==="
for d in ai-system-registry-backend monitoring-backend overview-backend alerts-backend compliance-backend decision-trace-analyzer-backend users-backend policy-checker-worker; do
  kubectl -n "$NS" rollout restart deploy/$d >/dev/null 2>&1
done
for d in ai-system-registry-backend alerts-backend users-backend; do
  kubectl -n "$NS" rollout status deploy/$d --timeout=150s 2>&1 | grep -avi memcache | tail -1
done
echo "=== verify register_resolver present in running image ==="
kubectl -n "$NS" exec deploy/ai-system-registry-backend -- sh -lc 'python -c "import ai_trust_tenancy as t; print(\"register_resolver:\", hasattr(t,\"register_resolver\"))"' 2>&1 | grep -avi memcache | head
kubectl -n "$NS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep -cE 'Running' | xargs echo "running pods:"
echo DONE
