#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config >/dev/null 2>&1
export KUBECONFIG="$SHOOT_KUBECONFIG"
GWNS=platform-mesh-system
echo "=== account-operator: image + args + env ==="
kubectl -n $GWNS get deploy account-operator -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}' 2>&1 | grep -avi memcache
echo "--- args ---"
kubectl -n $GWNS get deploy account-operator -o jsonpath='{range .spec.template.spec.containers[0].args[*]}{.}{"\n"}{end}' 2>&1 | grep -avi memcache
echo "--- env (name=value / secretRef) ---"
kubectl -n $GWNS get deploy account-operator -o jsonpath='{range .spec.template.spec.containers[0].env[*]}{.name}={.value}{" | "}{.valueFrom.secretKeyRef.name}/{.valueFrom.secretKeyRef.key}{"\n"}{end}' 2>&1 | grep -avi memcache
echo
echo "=== iam-service: image + args + env ==="
kubectl -n $GWNS get deploy iam-service -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}' 2>&1 | grep -avi memcache
echo "--- args ---"
kubectl -n $GWNS get deploy iam-service -o jsonpath='{range .spec.template.spec.containers[0].args[*]}{.}{"\n"}{end}' 2>&1 | grep -avi memcache
echo "--- env ---"
kubectl -n $GWNS get deploy iam-service -o jsonpath='{range .spec.template.spec.containers[0].env[*]}{.name}={.value}{" | "}{.valueFrom.secretKeyRef.name}/{.valueFrom.secretKeyRef.key}{" cm:"}{.valueFrom.configMapKeyRef.name}/{.valueFrom.configMapKeyRef.key}{"\n"}{end}' 2>&1 | grep -avi memcache
echo "--- mounted configmaps/secrets (volumes) ---"
kubectl -n $GWNS get deploy iam-service -o jsonpath='{range .spec.template.spec.volumes[*]}{.name}{" cm:"}{.configMap.name}{" secret:"}{.secret.secretName}{"\n"}{end}' 2>&1 | grep -avi memcache
