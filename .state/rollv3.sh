#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
echo "=== roll operator to v3 (mesh-IdP model: no per-tenant app-Keycloak job) ==="
kubectl -n "$NS" set image deploy/aitrust-mt-operator '*'=mirceacraciun795/aitrust-mt-operator:v3 2>&1 | grep -avi memcache
kubectl -n "$NS" rollout status deploy/aitrust-mt-operator --timeout=120s 2>&1 | grep -avi memcache | tail -1
echo "=== delete the obsolete crashlooping per-tenant realm jobs (v2 leftovers) ==="
kubectl -n "$NS" delete job -l tenant --ignore-not-found 2>&1 | grep -avi memcache
kubectl -n "$NS" delete job keycloak-provision --ignore-not-found 2>&1 | grep -avi memcache   # the shared app's own KC provision (abandoned; mesh KC used)
echo "=== give the operator a reconcile cycle, then check Subscription status ==="
sleep 30
kubectl get subscriptions.sub.aitrustmt.msp -A -o custom-columns='NS:.metadata.namespace,NAME:.metadata.name,READY:.status.ready,PHASE:.status.phase,REALM:.status.realm,URL:.status.url' 2>&1 | grep -avi memcache
echo "=== operator log (should show Ready, no job) ==="
kubectl -n "$NS" logs deploy/aitrust-mt-operator --tail=15 2>&1 | grep -avi memcache | grep -iE 'ready|realm|reconcil|error' | tail -8
echo DONE
