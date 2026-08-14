#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
# kubeconfig may have expired; re-mint if needed
kubectl -n "$NS" get ns >/dev/null 2>&1 || mint_shoot_kubeconfig 2>&1 | grep -avi memcache | tail -1
echo "=== roll backends + worker to SEC-L1 image ==="
for d in ai-system-registry-backend monitoring-backend overview-backend alerts-backend compliance-backend decision-trace-analyzer-backend users-backend policy-checker-worker; do
  kubectl -n "$NS" rollout restart deploy/$d >/dev/null 2>&1
done
for d in ai-system-registry-backend alerts-backend users-backend; do
  kubectl -n "$NS" rollout status deploy/$d --timeout=150s 2>&1 | grep -avi memcache | tail -1
done
echo "=== verify SEC-L1 guard is in the running image (config.validate refuses insecure jwt w/o opt-in) ==="
kubectl -n "$NS" exec deploy/ai-system-registry-backend -- sh -lc 'python -c "
import ai_trust_tenancy.config as c
print(\"ALLOW_INSECURE_JWT attr present:\", hasattr(c,\"ALLOW_INSECURE_JWT\"))
src=open(c.__file__).read()
print(\"validate refuses insecure jwt:\", \"TENANCY_ALLOW_INSECURE_JWT\" in src)
"' 2>&1 | grep -avi memcache | head
echo "=== app still healthy? ==="
kubectl -n "$NS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep -cE 'Running' | xargs echo "running pods:"
kubectl -n "$NS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep -vE 'Running|Completed' | awk '{print "  BAD: "$1" "$3}' || true
echo DONE
