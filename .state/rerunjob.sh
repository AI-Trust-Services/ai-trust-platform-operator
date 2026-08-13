#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
echo "=== restart operator (pull new v5) + delete failed job so it re-stamps ==="
kubectl -n "$NS" delete job kc-client-poc2 --ignore-not-found 2>&1 | grep -avi memcache
kubectl -n "$NS" rollout restart deploy/aitrust-mt-operator 2>&1 | grep -avi memcache
kubectl -n "$NS" rollout status deploy/aitrust-mt-operator --timeout=120s 2>&1 | grep -avi memcache | tail -1
echo "=== nudge reconcile (annotate the CR) ==="
kubectl -n "$NS" annotate subscriptions.sub.aitrustmt.msp test-poc2 reconcile="$(date +%s)" --overwrite 2>&1 | grep -avi memcache
sleep 15
echo "=== kc-client-poc2 job + logs ==="
kubectl -n "$NS" get job kc-client-poc2 --no-headers 2>&1 | grep -avi memcache
kubectl -n "$NS" logs job/kc-client-poc2 --tail=12 2>&1 | grep -avi memcache | tail -10
echo DONE
