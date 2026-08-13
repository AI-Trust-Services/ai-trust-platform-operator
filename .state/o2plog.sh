#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
echo "=== oauth2-proxy logs (last 40, filtered) ==="
POD=$(kubectl -n "$NS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep '^oauth2-proxy-' | grep Running | awk '{print $1}' | head -1)
echo "pod: $POD"
kubectl -n "$NS" logs "$POD" --tail=40 2>&1 | grep -avi memcache | grep -viE 'GET /ping|/ready' | tail -30
echo "=== current args (confirm) ==="
kubectl -n "$NS" get deploy oauth2-proxy -o jsonpath='{range .spec.template.spec.containers[0].args[*]}{@}{"\n"}{end}' 2>&1 | grep -avi memcache | grep -iE 'issuer|login|redeem|jwks|logout|skip|email|client-id'
echo DONE
