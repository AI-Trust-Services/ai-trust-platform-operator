#!/bin/bash
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh 2>/dev/null; load_config 2>/dev/null
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
f(){ grep -avi memcache; }
echo "=== oauth2-proxy-fridaytest last 25 lines (auth state now) ==="
kubectl -n "$NS" logs deploy/oauth2-proxy-fridaytest --tail=25 2>&1 | f | grep -iE 'No valid auth|AuthSuccess|sign_out|403|302|health|Initiating' | tail -20
