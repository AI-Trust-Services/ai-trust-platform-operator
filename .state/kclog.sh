#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
KCPOD=$(kubectl -n "$NS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep '^keycloak-[0-9a-f]' | awk '{print $1}' | head -1)
echo "kc pod: $KCPOD"
echo "=== keycloak startup logs (admin created? started? errors?) ==="
kubectl -n "$NS" logs "$KCPOD" 2>&1 | grep -avi memcache | grep -iE 'admin|bootstrap|started|Listening|ERROR|Added user|already' | tail -20
echo "=== effective admin env on the running pod ==="
kubectl -n "$NS" get pod "$KCPOD" -o jsonpath='{range .spec.containers[0].env[*]}{.name}{"\n"}{end}' 2>&1 | grep -avi memcache | grep -iE 'ADMIN|BOOTSTRAP'
echo "=== wait 25s (KC full start) then re-probe token ==="
sleep 25
kubectl -n "$NS" run t3-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet --command -- \
  sh -c 'curl -s -o /dev/null -w "http=%{http_code}\n" -d "client_id=admin-cli&username=admin&password=admin&grant_type=password" http://keycloak.aitrust-mt-msp.svc.cluster.local:8080/keycloak/realms/master/protocol/openid-connect/token' 2>&1 | grep -avi memcache | grep http=
echo DONE
