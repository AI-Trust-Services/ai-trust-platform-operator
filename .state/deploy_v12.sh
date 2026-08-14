#!/bin/bash
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
f(){ grep -avi memcache; }

echo "===== 1) roll operator to v12 ====="
kubectl -n "$NS" set image deploy/aitrust-mt-operator operator="$OPERATOR_IMAGE:$OPERATOR_TAG" 2>&1 | f
kubectl -n "$NS" rollout status deploy/aitrust-mt-operator --timeout=120s 2>&1 | f | tail -1
kubectl -n "$NS" logs deploy/aitrust-mt-operator --tail=10 2>&1 | f | grep -iE 'v12 starting' | tail -1

echo; echo "===== 2) update live portal ConfigMap (drop Plan + relabel Org) from the chart template's JSON ====="
# Extract the pm-content.json block from the updated template is complex (helm tpl); instead patch the
# live ConfigMap's createView.fields directly with the new JSON via a Python rewrite in a throwaway... 
# simpler: the live CM was kubectl-applied, so re-apply just the data. Build the new pm-content.json here.
