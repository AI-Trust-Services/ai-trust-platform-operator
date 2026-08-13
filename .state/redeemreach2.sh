#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
KC=http://keycloak-service.platform-mesh-system.svc.cluster.local:8080/keycloak/realms/poc2
echo "=== in-cluster reachability of mesh keycloak poc2 (from a pod in $NS) ==="
kubectl -n "$NS" run r-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet --command -- \
  sh -c "
    echo '-- discovery --'; curl -s -o /dev/null -w 'well-known: http=%{http_code}\n' $KC/.well-known/openid-configuration
    echo '-- token endpoint (empty POST -> expect 400 invalid_request, proving it is live) --'; curl -s -o /dev/null -w 'token: http=%{http_code}\n' -X POST $KC/protocol/openid-connect/token
    echo '-- certs (jwks) --'; curl -s -o /dev/null -w 'certs: http=%{http_code}\n' $KC/protocol/openid-connect/certs
  " 2>&1 | grep -avi memcache | grep -E 'http='
echo DONE
