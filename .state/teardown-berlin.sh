#!/bin/bash
# Tear down the phantom 'berlin' provisioning (demofriday2 subscription bound to a realm that
# does not exist). Removes the subscription + its per-org proxy/route/grant/secret + the kc-client
# job. Does NOT touch the mesh, other tenants, or any realm.
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
echo "=== find the demofriday2 subscription (mirrored ns) ==="
for row in $(kubectl get subscriptions.sub.aitrustmt.msp -A -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name}/{.spec.org}{"\n"}{end}' 2>/dev/null | grep -avi memcache); do
  echo "  $row"
done
echo "=== delete the berlin subscription(s) (org=berlin) ==="
kubectl get subscriptions.sub.aitrustmt.msp -A -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name}/{.spec.org}{"\n"}{end}' 2>/dev/null | grep -avi memcache | grep '/berlin$' | while IFS=/ read ns nm org; do
  echo "  deleting $ns/$nm (org=$org)"
  kubectl -n "$ns" delete subscriptions.sub.aitrustmt.msp "$nm" --timeout=60s 2>&1 | grep -avi memcache
done
echo "=== clean up org=berlin per-org resources (finalizer handles most; mop up the rest) ==="
kubectl -n "$NS" delete deploy,svc -l org=berlin --ignore-not-found 2>&1 | grep -avi memcache
kubectl -n "$NS" delete job kc-client-berlin --ignore-not-found 2>&1 | grep -avi memcache
kubectl -n "$NS" delete secret aitrust-mt-oauth2-berlin --ignore-not-found 2>&1 | grep -avi memcache
kubectl -n platform-mesh-system delete httproute aitrust-mt-berlin --ignore-not-found 2>&1 | grep -avi memcache
kubectl -n "$NS" delete referencegrant allow-gw-to-oauth2-berlin --ignore-not-found 2>&1 | grep -avi memcache
echo "=== verify gone ==="
kubectl -n "$NS" get deploy,svc,job,secret -l org=berlin --no-headers 2>&1 | grep -avi memcache || true
kubectl -n platform-mesh-system get httproute aitrust-mt-berlin --no-headers 2>&1 | grep -avi memcache || echo "  httproute gone"
echo DONE
