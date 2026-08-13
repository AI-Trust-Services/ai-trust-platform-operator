#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config >/dev/null 2>&1
export KUBECONFIG="$SHOOT_KUBECONFIG"
GWNS=platform-mesh-system
echo "=== CRDs related to fga/store/authorization/account/iam ==="
kubectl get crd 2>&1 | grep -avi memcache | grep -iE 'fga|store|authoriz|account|iam|role|openfga|platform-mesh' | head -40
echo
echo "=== openfga deploy: image + args (how store id passed?) ==="
kubectl -n $GWNS get deploy openfga -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}ARGS:{.spec.template.spec.containers[0].args}{"\n"}CMD:{.spec.template.spec.containers[0].command}{"\n"}' 2>&1 | grep -avi memcache
echo "--- openfga env ---"
kubectl -n $GWNS get deploy openfga -o jsonpath='{range .spec.template.spec.containers[0].env[*]}{.name}={.value}{"\n"}{end}' 2>&1 | grep -avi memcache | head -30
echo
echo "=== openfga service (in-cluster endpoint) ==="
kubectl -n $GWNS get svc 2>&1 | grep -avi memcache | grep -iE 'openfga|iam|keycloak' | head
