#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config
kubectl --kubeconfig "$SHOOT_KUBECONFIG" get ns >/dev/null 2>&1 || { rm -f "$SHOOT_KUBECONFIG"; mint_shoot_kubeconfig 2>&1 | grep -avi memcache | tail -1; }
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
echo "=== roll operator to v6 ==="
kubectl -n "$NS" set image deploy/aitrust-mt-operator operator="$OPERATOR_IMAGE:$OPERATOR_TAG" 2>&1 | grep -avi memcache
kubectl -n "$NS" rollout status deploy/aitrust-mt-operator --timeout=120s 2>&1 | grep -avi memcache | tail -1
echo "=== operator startup log (v6?) ==="
kubectl -n "$NS" logs deploy/aitrust-mt-operator --tail=30 2>&1 | grep -avi memcache | grep -iE 'v6 starting|refusing to provision|realm|Degraded' | tail -10
echo "=== give it ~20s to re-reconcile the existing subs, then check phases ==="
sleep 25
kubectl get subscriptions.sub.aitrustmt.msp -A -o jsonpath='{range .items[*]}{.metadata.name}  org={.spec.org}  phase={.status.phase}  msg={.status.conditions[0].message}{"\n"}{end}' 2>&1 | grep -avi memcache
echo "=== berlin: NO per-org resources should exist (gate refused) ==="
kubectl -n "$NS" get deploy,svc -l org=berlin --no-headers 2>&1 | grep -avi memcache || echo "  (none — good)"
kubectl -n platform-mesh-system get httproute aitrust-mt-berlin --no-headers 2>&1 | grep -avi memcache || echo "  (no berlin httproute — good)"
echo DONE
