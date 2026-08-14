#!/bin/bash
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
f(){ grep -avi memcache; }
echo "=== delete the failed v13 tenant-stores jobs so v14 re-stamps clean ==="
kubectl -n "$NS" delete jobs -l app.kubernetes.io/managed-by=aitrust-mt-operator --field-selector 2>/dev/null | f || true
for o in livedemo mirceatest mttest2 sohan fridaytest; do kubectl -n "$NS" delete job tenant-stores-$o --ignore-not-found 2>&1 | f; done
echo "=== build+push operator v14 (embeds fixed tenant-stores template) ==="
bash scripts/2-build-operator-image.sh 2>&1 | tail -4
echo "OP_EXIT: ${PIPESTATUS[0]}"
