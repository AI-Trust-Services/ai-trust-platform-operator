#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
echo "=== create a test Subscription with spec.org=poc2 ==="
cat <<EOF | kubectl apply -f - 2>&1 | grep -avi memcache
apiVersion: sub.aitrustmt.msp/v1alpha1
kind: Subscription
metadata: { name: test-poc2, namespace: $NS }
spec:
  displayName: "AI Trust MT — poc2 test"
  org: poc2
  adminEmail: "mircea.craciun@sap.com"
  plan: standard
EOF
echo "=== wait a bit for reconcile ==="
sleep 12
echo "=== operator logs ==="
kubectl -n "$NS" logs deploy/aitrust-mt-operator --tail=25 2>&1 | grep -avi memcache | grep -viE 'metrics|EventSource|Starting' | tail -20
echo "=== subscription status ==="
kubectl -n "$NS" get subscription test-poc2 -o jsonpath='phase={.status.phase} ready={.status.ready} url={.status.url} realm={.status.realm}{"\n"}' 2>&1 | grep -avi memcache
echo "=== per-org resources created? ==="
kubectl -n "$NS" get deploy,svc -l org=poc2 --no-headers 2>&1 | grep -avi memcache
kubectl -n "$NS" get job -l org=poc2 --no-headers 2>&1 | grep -avi memcache
kubectl -n platform-mesh-system get httproute -l org=poc2 --no-headers 2>&1 | grep -avi memcache
kubectl -n "$NS" get secret aitrust-mt-oauth2-poc2 --no-headers 2>&1 | grep -avi memcache
echo DONE
