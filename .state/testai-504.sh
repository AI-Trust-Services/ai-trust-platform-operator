#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"; LB=130.214.18.166
H=testai.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu
NS=aitp-33hins0iklcwfg45-testai
echo "=== 1) external GET / and timing (504 = gateway cannot reach backend) ==="
kubectl -n platform-mesh-system run e-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet -- \
  curl -sk -o /dev/null -w 'ext / : http=%{http_code} time=%{time_total}s\n' --resolve "$H:443:$LB" "https://$H/" 2>&1 | grep -av memcache | grep -E 'http=|time'
echo "=== 2) testai HTTPRoutes: exist + attached + point at the RIGHT backend ns/svc? ==="
for r in aitp-33hins0iklcwfg45-testai-app aitp-33hins0iklcwfg45-testai-keycloak; do
  echo "$r:"
  kubectl -n platform-mesh-system get httproute "$r" -o jsonpath='  section={.spec.parentRefs[0].sectionName} host={.spec.hostnames[0]} backend={.spec.rules[0].backendRefs[0].name}.{.spec.rules[0].backendRefs[0].namespace}:{.spec.rules[0].backendRefs[0].port} accepted={.status.parents[0].conditions[?(@.type=="Accepted")].status} resolved={.status.parents[0].conditions[?(@.type=="ResolvedRefs")].status}{"\n"}' 2>&1 | grep -av memcache
done
echo "=== 3) does the backend Service oauth2-proxy in the instance ns have endpoints? ==="
kubectl -n "$NS" get svc oauth2-proxy 2>&1 | grep -av memcache
kubectl -n "$NS" get endpoints oauth2-proxy 2>&1 | grep -av memcache
echo "=== 4) is the ReferenceGrant still there (cross-ns gateway->instance)? ==="
kubectl -n "$NS" get referencegrant 2>&1 | grep -av memcache | head
echo "=== 5) can we reach oauth2-proxy from a pod in the gateway ns (cross-ns svc DNS)? ==="
kubectl -n platform-mesh-system run x-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet -- \
  curl -sS -o /dev/null -w 'oauth2-proxy.<ns> :8080 -> http=%{http_code} time=%{time_total}s\n' "http://oauth2-proxy.$NS.svc.cluster.local:8080/ping" 2>&1 | grep -av memcache | grep -E 'http=|time|could not|resolve'
