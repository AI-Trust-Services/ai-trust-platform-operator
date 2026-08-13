#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
echo "=== delete test-poc2 Subscription (finalizer removes per-org proxy/route/svc/grant) ==="
kubectl -n "$NS" delete subscriptions.sub.aitrustmt.msp test-poc2 --timeout=60s 2>&1 | grep -avi memcache
echo "=== also delete leftovers by org label (client Job + secret aren't finalizer-removed) ==="
kubectl -n "$NS" delete job kc-client-poc2 --ignore-not-found 2>&1 | grep -avi memcache
kubectl -n "$NS" delete secret aitrust-mt-oauth2-poc2 --ignore-not-found 2>&1 | grep -avi memcache
kubectl -n "$NS" delete deploy,svc -l org=poc2 --ignore-not-found 2>&1 | grep -avi memcache
kubectl -n platform-mesh-system delete httproute aitrust-mt-poc2 --ignore-not-found 2>&1 | grep -avi memcache
kubectl -n "$NS" delete referencegrant allow-gw-to-oauth2-poc2 --ignore-not-found 2>&1 | grep -avi memcache
echo "=== verify gone ==="
kubectl -n "$NS" get deploy,svc,job,secret -l org=poc2 --no-headers 2>&1 | grep -avi memcache || true
kubectl -n "$NS" get subscriptions.sub.aitrustmt.msp --no-headers 2>&1 | grep -avi memcache
echo "NOTE: the aitrust-mt-app client left in the poc2 realm is harmless (idempotent) — leaving it."
echo DONE
