#!/bin/bash
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
f(){ grep -avi memcache; }
echo "=== FULL tenant-stores-mirceatest log (all lines, look for role errors) ==="
kubectl -n "$NS" logs job/tenant-stores-mirceatest 2>&1 | f | grep -ivE 'greenlet|_concurrency|await_only|site-packages/sqlalchemy|switch\(' | tail -40
