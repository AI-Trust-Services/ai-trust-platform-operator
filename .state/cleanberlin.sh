#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
echo "=== remove STALE berlin per-org resources left by the old v5 operator (gate refuses new ones) ==="
kubectl -n "$NS" delete deploy,svc -l org=berlin --ignore-not-found 2>&1 | grep -avi memcache
kubectl -n "$NS" delete secret aitrust-mt-oauth2-berlin --ignore-not-found 2>&1 | grep -avi memcache
kubectl -n "$NS" delete job kc-client-berlin --ignore-not-found 2>&1 | grep -avi memcache
kubectl -n "$NS" delete referencegrant allow-gw-to-oauth2-berlin --ignore-not-found 2>&1 | grep -avi memcache
kubectl -n platform-mesh-system delete httproute aitrust-mt-berlin --ignore-not-found 2>&1 | grep -avi memcache
echo "=== wait + confirm the v6 gate does NOT re-create them ==="
sleep 20
echo "-- berlin resources (expect none) --"
kubectl -n "$NS" get deploy,svc -l org=berlin --no-headers 2>&1 | grep -avi memcache || echo "  (none)"
kubectl -n platform-mesh-system get httproute aitrust-mt-berlin --no-headers 2>&1 | grep -avi memcache || echo "  (no httproute)"
echo "-- berlin sub still Degraded (correct) --"
kubectl -n 220lfo6jvh066w7s get subscriptions.sub.aitrustmt.msp demofriday2 -o jsonpath='{.status.phase}: {.status.conditions[0].message}{"\n"}' 2>&1 | grep -avi memcache
echo DONE
