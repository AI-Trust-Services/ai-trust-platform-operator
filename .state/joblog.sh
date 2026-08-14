#!/bin/bash
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
f(){ grep -avi memcache; }
echo "=== FULL tenant-stores-mirceatest log (alembic + grant) ==="
kubectl -n "$NS" logs job/tenant-stores-mirceatest --tail=60 2>&1 | f | grep -ivE 'greenlet|_concurrency|await_only|switch\(|site-packages/sqlalchemy' | head -50
