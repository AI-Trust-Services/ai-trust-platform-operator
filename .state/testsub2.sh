#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
echo "=== subscription status (FQN) ==="
kubectl -n "$NS" get subscriptions.sub.aitrustmt.msp test-poc2 -o jsonpath='phase={.status.phase} ready={.status.ready}{"\n"}url={.status.url}{"\n"}realm={.status.realm} tenantId={.status.tenantId}{"\n"}msg={.status.conditions[0].message}{"\n"}' 2>&1 | grep -avi memcache
echo "=== kc-client-poc2 Job status + logs ==="
kubectl -n "$NS" get job kc-client-poc2 --no-headers 2>&1 | grep -avi memcache
kubectl -n "$NS" logs job/kc-client-poc2 --tail=15 2>&1 | grep -avi memcache | tail -12
echo "=== oauth2-proxy-poc2 pod logs (did it start OK against poc2 realm?) ==="
kubectl -n "$NS" logs deploy/oauth2-proxy-poc2 --tail=12 2>&1 | grep -avi memcache | grep -viE 'GET /ping' | tail -10
echo DONE
