#!/bin/bash
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh 2>/dev/null; load_config 2>/dev/null
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
f(){ grep -avi memcache; }

echo "===== full recent oauth2-proxy-fridaytest log (last 30 lines, all) ====="
kubectl -n "$NS" logs deploy/oauth2-proxy-fridaytest --tail=30 2>&1 | f | tail -30

echo; echo "===== the proxy's sign_out-related flags ====="
kubectl -n "$NS" get deploy oauth2-proxy-fridaytest -o jsonpath='{range .spec.template.spec.containers[0].args[*]}{@}{"\n"}{end}' 2>&1 | f | grep -iE 'logout|sign_out|redirect|whitelist|cookie-domain'
echo DONE
