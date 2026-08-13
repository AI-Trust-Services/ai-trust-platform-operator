#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config
rm -f "$SHOOT_KUBECONFIG"
mint_shoot_kubeconfig
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
echo "=== all backend pods ==="
kubectl -n "$NS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep -E 'backend|shell|policy-checker' | awk '{printf "%-52s %-6s %s\n",$1,$2,$3}'
echo "=== tenancy import present in running registry image? ==="
kubectl -n "$NS" exec deploy/ai-system-registry-backend -- sh -lc 'python -c "import ai_trust_tenancy; from ai_trust_tenancy import install_tenant_middleware, install_tenant_scoping; print(\"tenancy OK\")"' 2>&1 | grep -avi memcache | head -3
echo "=== worker logs (tenant loop) ==="
kubectl -n "$NS" logs deploy/policy-checker-worker --tail=20 2>&1 | grep -avi memcache | grep -iE 'started|tenant_pass|evaluating|error|OWNER' | head -8
echo DONE
