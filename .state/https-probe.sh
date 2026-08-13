#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
echo "=== A) can KC serve HTTPS directly? (KC_HTTPS_* env / does it listen on 8443?) ==="
KCPOD=$(kubectl -n "$NS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep '^keycloak-[0-9a-f]' | awk '{print $1}' | head -1)
kubectl -n "$NS" get pod "$KCPOD" -o jsonpath='{range .spec.containers[0].env[*]}{.name}{"\n"}{end}' 2>&1 | grep -avi memcache | grep -iE 'HTTPS|HTTP_ENABLED|PROXY|HOSTNAME'
echo "-- keycloak Service ports --"
kubectl -n "$NS" get svc keycloak -o jsonpath='{range .spec.ports[*]}{.name}={.port}->{.targetPort}{"\n"}{end}' 2>&1 | grep -avi memcache
echo
echo "=== B) the mesh gateway route for the shared app host — does it front /keycloak over HTTPS? ==="
kubectl -n platform-mesh-system get httproute aitrust-mt-shared-app -o jsonpath='hosts={.spec.hostnames} backend={.spec.rules[0].backendRefs[0].name}:{.spec.rules[0].backendRefs[0].port}{"\n"}' 2>&1 | grep -avi memcache
echo "-- so https://<shared-host>/keycloak/... goes through oauth2-proxy — is /keycloak public (not behind login)? --"
echo
echo "=== C) is oauth2-proxy configured to pass /keycloak through unauthenticated (skip-auth)? ==="
kubectl -n "$NS" get deploy oauth2-proxy -o jsonpath='{range .spec.template.spec.containers[0].args[*]}{@}{"\n"}{end}' 2>&1 | grep -avi memcache | grep -iE 'skip-auth|keycloak|upstream'
echo
echo "=== D) what CA would the provisioner need to trust for the mesh HTTPS? (served cert issuer on the shared host) ==="
LB=130.214.18.166
kubectl -n "$NS" run co-$RANDOM --rm -i --restart=Never --image=alpine/openssl --quiet --command -- \
  sh -c "echo | openssl s_client -connect $LB:443 -servername $SHARED_APP_HOST 2>/dev/null | openssl x509 -noout -issuer 2>/dev/null" 2>&1 | grep -avi memcache | grep -i issuer
echo DONE
