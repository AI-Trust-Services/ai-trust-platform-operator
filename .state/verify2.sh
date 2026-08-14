#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp; LB=130.214.18.166
H=ai-trust-mt-mttest.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu
echo "=== A. FULL response headers on the edge (look for CSP/HSTS/nosniff/frame; NO acao=*) ==="
kubectl -n "$NS" run h-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet --command -- \
  sh -c "curl -sk -D - -o /dev/null --resolve $H:443:$LB https://$H/oauth2/sign_in" 2>&1 | grep -avi memcache | grep -iE 'content-security|x-frame|strict-transport|x-content-type|referrer|access-control' || echo "(none of those headers found)"
echo "=== B. TENANCY_MODE actual value (configmap) ==="
kubectl -n "$NS" exec deploy/ai-system-registry-backend -- sh -lc 'echo TENANCY_MODE=$TENANCY_MODE; echo TENANT_CLAIM=$TENANT_CLAIM' 2>&1 | grep -avi memcache
echo "=== C. resolver: confirm X-Tenant-Id NOT read in jwt path ==="
kubectl -n "$NS" exec deploy/ai-system-registry-backend -- sh -lc 'python -c "
import ai_trust_tenancy.resolver as r, inspect
src=inspect.getsource(r)
# in jwt branch the tenant must come from the token, not the header
jwt_branch = src.split(\"MODE ==\")
print(\"resolver source has header-mode-only override:\", src.count(\"request.headers.get(TENANT_HEADER\")==1)
print(\"jwt path calls _verify_and_decode:\", \"_verify_and_decode(token)\" in src)
"' 2>&1 | grep -avi memcache
echo DONE
