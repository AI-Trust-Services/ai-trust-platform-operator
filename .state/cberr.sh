#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
POD=$(kubectl -n "$NS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep '^oauth2-proxy-' | grep Running | awk '{print $1}' | head -1)
echo "pod: $POD"
echo "=== oauth2-proxy logs (last 60, callback/redeem/error) ==="
kubectl -n "$NS" logs "$POD" --tail=80 2>&1 | grep -avi memcache | grep -viE 'GET /ping|/ready|bulma|all.min|webfonts|favicon' | tail -40
echo DONE
