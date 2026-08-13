#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
echo "=== current backend/users deploy state ==="
kubectl -n "$NS" get deploy 2>&1 | grep -avi memcache | grep -E 'backend|users|NAME'
echo "=== did the openfga-provision job run + is store ai-trust-mt created? ==="
kubectl -n "$NS" get job openfga-provision 2>&1 | grep -avi memcache
kubectl -n "$NS" get pods 2>&1 | grep -avi memcache | grep openfga-provision
echo "-- provision job logs (store id + roles seeded?) --"
PP=$(kubectl -n "$NS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep openfga-provision | awk '{print $1}' | head -1)
[ -n "$PP" ] && kubectl -n "$NS" logs "$PP" --tail=20 2>&1 | grep -avi memcache | tail -20
echo "=== does the mesh openfga now have a store named ai-trust-mt? ==="
kubectl -n "$NS" run q-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet --command -- \
  sh -c 'curl -s http://openfga.platform-mesh-system.svc.cluster.local:8080/stores' 2>&1 | grep -avi memcache | tr ',' '\n' | grep -iE 'ai-trust-mt|"id"' | head
echo DONE
