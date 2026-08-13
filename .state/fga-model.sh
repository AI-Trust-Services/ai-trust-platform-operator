#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
GWNS=platform-mesh-system
echo "=== mesh OpenFGA endpoint + how to reach it in-cluster ==="
kubectl -n "$GWNS" get svc openfga -o jsonpath='openfga svc ports: {range .spec.ports[*]}{.name}={.port} {end}{"\n"}' 2>&1 | grep -avi memcache
echo "=== the tenant store (org aitrustmt) — id + current authorization model types ==="
setup_kcp >/dev/null 2>&1; kcp_portforward >/dev/null 2>&1
for i in $(seq 1 12); do kc root get workspace >/dev/null 2>&1 && break; sleep 2; done
kc root:orgs get store aitrustmt -o jsonpath='storeId={.status.storeId} modelId={.status.authorizationModelId}{"\n"}' 2>&1 | grep -avi memcache
echo "-- the store's coreModule (authz model DSL) — first 40 lines to see the type set --"
kc root:orgs get store aitrustmt -o jsonpath='{.spec.coreModule}' 2>&1 | grep -avi memcache | head -40
echo "=== can we write a NEW authorization model to that store? (list existing models via the mesh openfga API) ==="
SID=$(kc root:orgs get store aitrustmt -o jsonpath='{.status.storeId}' 2>/dev/null | grep -avi memcache)
echo "storeId=$SID"
kubectl -n "$GWNS" run fga-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet --command -- \
  sh -c "curl -s -o /dev/null -w 'list models: http=%{http_code}\n' http://openfga.$GWNS.svc.cluster.local:8080/stores/$SID/authorization-models" 2>&1 | grep -avi memcache | grep http=
echo DONE
