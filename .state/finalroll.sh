#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
kubectl -n "$NS" rollout restart deploy/decision-trace-analyzer-backend >/dev/null 2>&1
kubectl -n "$NS" rollout status deploy/decision-trace-analyzer-backend --timeout=150s 2>&1 | grep -avi memcache | tail -1
echo "=== all backend pods status ==="
kubectl -n "$NS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep -E 'backend|shell|policy-checker' | awk '{printf "%-52s %-6s %s\n",$1,$2,$3}'
echo "=== confirm tenancy code now IN the running registry image ==="
kubectl -n "$NS" exec deploy/ai-system-registry-backend -- sh -lc 'python -c "import ai_trust_tenancy; print(\"tenancy import OK:\", ai_trust_tenancy.__file__)"' 2>&1 | grep -avi memcache | head -3
echo "=== worker: tenant-loop + OWNER url present? ==="
kubectl -n "$NS" logs deploy/policy-checker-worker --tail=15 2>&1 | grep -avi memcache | grep -iE 'started|tenant_pass|evaluating|error' | head -8
echo DONE
