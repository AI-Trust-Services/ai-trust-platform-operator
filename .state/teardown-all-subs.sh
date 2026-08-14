#!/bin/bash
# Tear down ALL sub.aitrustmt.msp Subscriptions + their per-org resources (oauth2-proxy,
# Service, HTTPRoute, ReferenceGrant, client secret, kc-client Job). Clean slate for re-subscribing.
# Does NOT touch: the shared app, Postgres/ClickHouse/MinIO data, the mesh, or any Keycloak realm.
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp; GWNS=platform-mesh-system

echo "=== 1. delete every Subscription (finalizer removes most per-org resources) ==="
kubectl get subscriptions.sub.aitrustmt.msp -A -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name}{"\n"}{end}' 2>/dev/null | grep -avi memcache | while IFS=/ read ns nm; do
  [ -n "$nm" ] || continue
  echo "  deleting $ns/$nm"
  kubectl -n "$ns" delete subscriptions.sub.aitrustmt.msp "$nm" --timeout=60s 2>&1 | grep -avi memcache
done

echo "=== 2. mop up ALL per-org resources by label (org=*) in the provider ns ==="
kubectl -n "$NS" delete deploy,svc -l app=oauth2-proxy-org --ignore-not-found 2>&1 | grep -avi memcache
# per-org secrets + kc-client jobs (labeled managed-by the operator, org=<x>)
kubectl -n "$NS" delete secret -l app.kubernetes.io/managed-by=aitrust-mt-operator --ignore-not-found 2>&1 | grep -avi memcache
kubectl -n "$NS" delete job -l app.kubernetes.io/managed-by=aitrust-mt-operator --ignore-not-found 2>&1 | grep -avi memcache
kubectl -n "$NS" delete referencegrant -l app.kubernetes.io/managed-by=aitrust-mt-operator --ignore-not-found 2>&1 | grep -avi memcache

echo "=== 3. mop up per-org HTTPRoutes in the gateway ns ==="
kubectl -n "$GWNS" delete httproute -l app.kubernetes.io/managed-by=aitrust-mt-operator --ignore-not-found 2>&1 | grep -avi memcache

echo "=== VERIFY: subscriptions + per-org resources gone ==="
echo "-- subscriptions --"; kubectl get subscriptions.sub.aitrustmt.msp -A --no-headers 2>&1 | grep -avi memcache || echo "  none"
echo "-- oauth2-proxy-org deploys --"; kubectl -n "$NS" get deploy -l app=oauth2-proxy-org --no-headers 2>&1 | grep -avi memcache || echo "  none"
echo "-- per-org httproutes --"; kubectl -n "$GWNS" get httproute -l app.kubernetes.io/managed-by=aitrust-mt-operator --no-headers 2>&1 | grep -avi memcache || echo "  none"
echo "=== shared app untouched? (should still be Running) ==="
kubectl -n "$NS" get deploy shell ai-system-registry-backend --no-headers 2>&1 | grep -avi memcache
echo DONE
