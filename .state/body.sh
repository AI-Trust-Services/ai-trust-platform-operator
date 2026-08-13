#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
echo "=== FULL response body of the 403 (svc dns) — the reason ==="
kubectl -n "$NS" run tb-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet --command -- \
  sh -c 'curl -s -w "\nHTTP=%{http_code}\n" -d "client_id=admin-cli&username=admin&password=admin&grant_type=password" http://keycloak.aitrust-mt-msp.svc.cluster.local:8080/keycloak/realms/master/protocol/openid-connect/token' 2>&1 | grep -avi memcache | tail -8
echo "=== compare: token via short host keycloak:8080 (provisioner's KEYCLOAK_URL host) ==="
kubectl -n "$NS" run ts-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet --command -- \
  sh -c 'curl -s -w "\nHTTP=%{http_code}\n" -d "client_id=admin-cli&username=admin&password=admin&grant_type=password" http://keycloak:8080/keycloak/realms/master/protocol/openid-connect/token' 2>&1 | grep -avi memcache | tail -8
echo "=== KC hostname-related env ==="
KCPOD=$(kubectl -n "$NS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep '^keycloak-[0-9a-f]' | awk '{print $1}' | head -1)
kubectl -n "$NS" get pod "$KCPOD" -o jsonpath='{range .spec.containers[0].env[*]}{.name}={.value}{"\n"}{end}' 2>&1 | grep -avi memcache | grep -iE 'HOSTNAME|HTTP|PROXY|FRONTEND'
echo DONE
