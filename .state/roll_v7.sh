#!/bin/bash
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh 2>/dev/null; load_config 2>/dev/null
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
f(){ grep -avi memcache; }

echo "===== 1) roll operator to v7 ====="
kubectl -n "$NS" set image deploy/aitrust-mt-operator operator="$OPERATOR_IMAGE:$OPERATOR_TAG" 2>&1 | f
kubectl -n "$NS" rollout status deploy/aitrust-mt-operator --timeout=120s 2>&1 | f | tail -1
kubectl -n "$NS" logs deploy/aitrust-mt-operator --tail=8 2>&1 | f | grep -iE 'starting|v6|v7' | tail -3

echo; echo "===== 2) roll users-backend (pull new :aitrust-mt) ====="
kubectl -n "$NS" rollout restart deploy/users-backend 2>&1 | f
kubectl -n "$NS" rollout status deploy/users-backend --timeout=150s 2>&1 | f | tail -1
echo "  users-backend env sanity (TENANCY_MODE + mesh admin present?):"
kubectl -n "$NS" get deploy users-backend -o jsonpath='{range .spec.template.spec.containers[0].env[*]}{.name}{"\n"}{end}' 2>&1 | f | grep -iE 'TENANCY_MODE|MESH_KC_ADMIN' | sed 's/^/    /'

echo; echo "===== 3) list current subscriptions (orgs to re-stamp) ====="
kubectl get subscriptions.sub.aitrustmt.msp -A -o jsonpath='{range .items[*]}{.spec.org}={.status.phase}{"\n"}{end}' 2>&1 | f | grep -vE '^=' | sort -u

echo DONE_STEP123
