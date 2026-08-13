#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
echo "=== db-migrate-0009 pod status ==="
kubectl -n "$NS" get pods -l job-name=db-migrate-0009 --no-headers 2>&1 | grep -avi memcache
P=$(kubectl -n "$NS" get pods -l job-name=db-migrate-0009 --no-headers 2>/dev/null | grep -avi memcache | awk '{print $1}' | head -1)
echo "pod: $P"
echo "--- describe (events) ---"
kubectl -n "$NS" describe pod "$P" 2>&1 | grep -avi memcache | grep -iE 'State:|Reason:|Events:|Warning|Pulling|Pulled|Started|Created|Failed|node' | head -20
echo "--- logs (if any) ---"
kubectl -n "$NS" logs "$P" --tail=40 2>&1 | grep -avi memcache | tail -40
echo DONE
