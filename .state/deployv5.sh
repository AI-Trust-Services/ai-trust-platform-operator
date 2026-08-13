#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
STOREID=$(kubectl -n "$NS" get deploy ai-system-registry-backend -o jsonpath='{range .spec.template.spec.containers[0].env[?(@.name=="OPENFGA_STORE_ID")]}{.value}{end}' 2>/dev/null | grep -avi memcache)
echo "shared store id: $STOREID"
SUFFIX="ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu"

echo "=== set operator image v5 + new env ==="
kubectl -n "$NS" set image deploy/aitrust-mt-operator operator="$OPERATOR_IMAGE:$OPERATOR_TAG" 2>&1 | grep -avi memcache
kubectl -n "$NS" set env deploy/aitrust-mt-operator \
  INSTANCE_DOMAIN_SUFFIX="$SUFFIX" \
  GATEWAY_SECTION="terminate-wildstar" \
  KC_INTERNAL_URL="http://keycloak-service.platform-mesh-system.svc.cluster.local:8080/keycloak" \
  KC_PUBLIC_URL="https://$SUFFIX/keycloak" \
  OPENFGA_URL="http://openfga.platform-mesh-system.svc.cluster.local:8080" \
  OPENFGA_STORE_ID="$STOREID" 2>&1 | grep -avi memcache
kubectl -n "$NS" rollout status deploy/aitrust-mt-operator --timeout=120s 2>&1 | grep -avi memcache | tail -1
echo "=== operator logs (startup) ==="
kubectl -n "$NS" logs deploy/aitrust-mt-operator --tail=15 2>&1 | grep -avi memcache | tail -12
echo DONE
