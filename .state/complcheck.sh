#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
kubectl -n "$NS" rollout status deploy/compliance-backend --timeout=120s 2>&1 | grep -avi memcache | tail -1
kubectl -n "$NS" get deploy compliance-backend --no-headers 2>&1 | grep -avi memcache
echo "--- if still not ready, last pod logs ---"
P=$(kubectl -n "$NS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep '^compliance-backend-' | awk '{print $1}' | tail -1)
kubectl -n "$NS" get pod "$P" --no-headers 2>&1 | grep -avi memcache
kubectl -n "$NS" logs "$P" --tail=8 2>&1 | grep -avi memcache | grep -viE '/health' | tail -8
echo DONE
