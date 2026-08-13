#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
echo "=== confirm MT stack is in $NS (keycloak + provision) ==="
kubectl -n "$NS" get deploy keycloak 2>&1 | grep -avi memcache
echo "=== does admin/admin work via DIRECT in-cluster HTTP to the KC service? (the correct path) ==="
kubectl -n "$NS" run d-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet --command -- \
  sh -c 'curl -sS -o /dev/null -w "direct keycloak:8080/keycloak token: http=%{http_code}\n" -H "Content-Type: application/x-www-form-urlencoded" --data-urlencode client_id=admin-cli --data-urlencode username=admin --data-urlencode password=admin --data-urlencode grant_type=password http://keycloak.aitrust-mt-msp.svc.cluster.local:8080/keycloak/realms/master/protocol/openid-connect/token' 2>&1 | grep -avi memcache | grep http=
echo "=== also try the ROOT path (in case this KC serves at / not /keycloak) ==="
kubectl -n "$NS" run r-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet --command -- \
  sh -c 'curl -sS -o /dev/null -w "direct keycloak:8080 (root) token: http=%{http_code}\n" -H "Content-Type: application/x-www-form-urlencoded" --data-urlencode client_id=admin-cli --data-urlencode username=admin --data-urlencode password=admin --data-urlencode grant_type=password http://keycloak.aitrust-mt-msp.svc.cluster.local:8080/realms/master/protocol/openid-connect/token' 2>&1 | grep -avi memcache | grep http=
echo "=== what KEYCLOAK_URL did the shared app's OWN provision job use, and did it Complete? ==="
kubectl -n "$NS" get job keycloak-provision -o jsonpath='status={.status.conditions[0].type}{"\n"}' 2>&1 | grep -avi memcache
kubectl -n "$NS" get pods 2>&1 | grep -avi memcache | grep keycloak-provision
echo DONE
