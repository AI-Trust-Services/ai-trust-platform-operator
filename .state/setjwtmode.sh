#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
echo "=== set TENANCY_MODE=jwt + TENANT_CLAIM=tenant_id on all backends + worker ==="
for d in ai-system-registry-backend monitoring-backend overview-backend alerts-backend compliance-backend decision-trace-analyzer-backend users-backend policy-checker-worker; do
  kubectl -n "$NS" set env deploy/$d TENANCY_MODE=jwt TENANT_CLAIM=tenant_id >/dev/null 2>&1 && echo "  set $d"
done
echo "=== wait for rollout (set env triggers a new rollout) ==="
for d in ai-system-registry-backend alerts-backend compliance-backend decision-trace-analyzer-backend monitoring-backend users-backend; do
  kubectl -n "$NS" rollout status deploy/$d --timeout=150s 2>&1 | grep -avi memcache | tail -1
done
echo "=== confirm resolver MODE now jwt ==="
kubectl -n "$NS" exec deploy/ai-system-registry-backend -- sh -lc 'python -c "from ai_trust_tenancy.config import MODE; print(\"MODE=\",MODE)"' 2>&1 | grep -avi memcache | head
echo DONE
