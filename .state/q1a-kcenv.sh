#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config >/dev/null 2>&1
export KUBECONFIG="$SHOOT_KUBECONFIG"
GWNS=platform-mesh-system
echo "=== keycloak-0 relevant env (admin creds + relative path) ==="
kubectl -n $GWNS get statefulset keycloak -o jsonpath='{range .spec.template.spec.containers[0].env[*]}{.name}={.value} | secret:{.valueFrom.secretKeyRef.name}/{.valueFrom.secretKeyRef.key}{"\n"}{end}' 2>&1 | grep -avi memcache | grep -iE 'ADMIN|RELATIVE|HTTP|HOSTNAME|PROXY'
echo
echo "=== secrets in ns that look like KC admin ==="
kubectl -n $GWNS get secret 2>&1 | grep -avi memcache | grep -iE 'keycloak|admin|credential|initial' | head
echo
echo "=== keycloak-0 all env names (for reference) ==="
kubectl -n $GWNS get statefulset keycloak -o jsonpath='{range .spec.template.spec.containers[0].env[*]}{.name}{"\n"}{end}' 2>&1 | grep -avi memcache | head -40
