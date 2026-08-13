#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config >/dev/null 2>&1
export KUBECONFIG="$SHOOT_KUBECONFIG"
GWNS=platform-mesh-system
echo "=== iam-service full container spec (command/args/mounts) ==="
kubectl -n $GWNS get deploy iam-service -o jsonpath='{.spec.template.spec.containers[0].command}{"\n"}ARGS:{.spec.template.spec.containers[0].args}{"\n"}MOUNTS:{range .spec.template.spec.containers[0].volumeMounts[*]}{.name}@{.mountPath}{" "}{end}{"\n"}' 2>&1 | grep -avi memcache
echo
echo "=== account-operator full container spec ==="
kubectl -n $GWNS get deploy account-operator -o jsonpath='{.spec.template.spec.containers[0].command}{"\n"}ARGS:{.spec.template.spec.containers[0].args}{"\n"}' 2>&1 | grep -avi memcache
echo
echo "=== CONFIGMAP iam-service-roles (FULL DUMP) ==="
kubectl -n $GWNS get cm iam-service-roles -o yaml 2>&1 | grep -avi memcache
