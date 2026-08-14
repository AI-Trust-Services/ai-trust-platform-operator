#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
echo "=== all backend pods ==="
kubectl -n "$NS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep -E 'backend|worker' | awk '{printf "%-52s %-6s %s %s\n",$1,$2,$3,$4}'
echo "=== compliance-backend latest pod logs (why not ready?) ==="
P=$(kubectl -n "$NS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep '^compliance-backend-' | awk '{print $1}' | tail -1)
echo "pod: $P"
kubectl -n "$NS" logs "$P" --tail=25 2>&1 | grep -avi memcache | grep -viE 'GET /health' | tail -25
echo DONE
