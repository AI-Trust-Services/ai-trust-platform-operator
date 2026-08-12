#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config

echo "=== 0. gateway deployments present in $MESH_NS ==="
sk -n "$MESH_NS" get deploy | grep -av memcache | grep -iE 'NAME|graphql'

echo
echo "=== 1. restart gateway + listener ==="
sk -n "$MESH_NS" rollout restart deploy/kubernetes-graphql-gateway 2>&1 | grep -av memcache
sk -n "$MESH_NS" rollout restart deploy/kubernetes-graphql-gateway-listener 2>&1 | grep -av memcache

echo
echo "=== 2. wait for rollout ==="
KUBECONFIG="$SHOOT_KUBECONFIG" kubectl -n "$MESH_NS" rollout status deploy/kubernetes-graphql-gateway --timeout=150s 2>&1 | grep -av memcache | tail -2
KUBECONFIG="$SHOOT_KUBECONFIG" kubectl -n "$MESH_NS" rollout status deploy/kubernetes-graphql-gateway-listener --timeout=150s 2>&1 | grep -av memcache | tail -2

echo
echo "=== 3. let listener reconcile all clusters (30s) ==="
sleep 30

echo
echo "=== 4a. LISTENER logs (--since=3m) mentioning aitrust / cluster / schema / undefined / error ==="
sk -n "$MESH_NS" logs deploy/kubernetes-graphql-gateway-listener --since=3m 2>&1 | grep -av memcache \
  | grep -iE 'aitrust|aitrustg2|ai-trust|trust\.ai|undefined|schema|generat|error|fail|reconcil' | tail -60

echo
echo "=== 4b. LISTENER: explicit 'schema not found' / 'undefined' hits ==="
sk -n "$MESH_NS" logs deploy/kubernetes-graphql-gateway-listener --since=3m 2>&1 | grep -av memcache \
  | grep -iE 'schema not found|undefined' | tail -30

echo
echo "=== 4c. GATEWAY logs (--since=3m) — schema generation for aitrust ==="
sk -n "$MESH_NS" logs deploy/kubernetes-graphql-gateway --since=3m 2>&1 | grep -av memcache \
  | grep -iE 'aitrust|ai-trust|trust\.ai|undefined|schema|generat|error|fail' | tail -40
