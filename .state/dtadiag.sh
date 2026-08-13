#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
echo "=== dta backend pods ==="
kubectl -n "$NS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep decision-trace-analyzer-backend
P=$(kubectl -n "$NS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep 'decision-trace-analyzer-backend' | grep -v Running | awk '{print $1}' | head -1)
[ -z "$P" ] && P=$(kubectl -n "$NS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep 'decision-trace-analyzer-backend' | awk '{print $1}' | tail -1)
echo "pod: $P"
echo "--- logs ---"
kubectl -n "$NS" logs "$P" --tail=30 2>&1 | grep -avi memcache | tail -30
echo "--- describe events ---"
kubectl -n "$NS" describe pod "$P" 2>&1 | grep -avi memcache | grep -iE 'State:|Reason:|Back-off|Error|Warning|Pulling|Pulled|Started|CrashLoop' | head -15
echo DONE
