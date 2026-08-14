#!/bin/bash
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh 2>/dev/null; load_config 2>/dev/null
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
f(){ grep -avi memcache; }

echo "===== roll operator to v8 ====="
kubectl -n "$NS" set image deploy/aitrust-mt-operator operator="$OPERATOR_IMAGE:$OPERATOR_TAG" 2>&1 | f
kubectl -n "$NS" rollout status deploy/aitrust-mt-operator --timeout=120s 2>&1 | f | tail -1

echo; echo "===== re-stamp fridaytest (delete job so v8 operator recreates it) ====="
kubectl -n "$NS" delete job kc-client-fridaytest --ignore-not-found 2>&1 | f
SUB=$(kubectl get subscriptions.sub.aitrustmt.msp -A -o jsonpath='{range .items[?(@.spec.org=="fridaytest")]}{.metadata.namespace}/{.metadata.name}{"\n"}{end}' 2>/dev/null | head -1)
SNS="${SUB%%/*}"; SNAME="${SUB##*/}"
kubectl -n "$SNS" annotate subscriptions.sub.aitrustmt.msp "$SNAME" restamp=v8 --overwrite 2>&1 | f

echo; echo "===== wait for kc-client-fridaytest to complete (v8) ====="
for i in $(seq 1 12); do
  ST=$(kubectl -n "$NS" get job kc-client-fridaytest -o jsonpath='{.status.succeeded}/{.status.failed}' 2>/dev/null | grep -avi memcache)
  POD=$(kubectl -n "$NS" get pods -l job-name=kc-client-fridaytest --no-headers 2>/dev/null | grep -avi memcache | tail -1)
  echo "  [$i] job succeeded/failed=$ST  pod: $POD"
  echo "$POD" | grep -q Completed && break
  sleep 8
done
echo "-- job log --"
kubectl -n "$NS" logs job/kc-client-fridaytest --tail=12 2>&1 | f | tail -12
echo DONE
