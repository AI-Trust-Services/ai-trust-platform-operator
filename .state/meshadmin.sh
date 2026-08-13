#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
GWNS=platform-mesh-system
echo "=== mesh keycloak admin: where are the bootstrap creds? ==="
KCPOD=$(kubectl -n "$GWNS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep -E '^keycloak-[0-9]' | awk '{print $1}' | head -1)
echo "kc pod: $KCPOD"
kubectl -n "$GWNS" get pod "$KCPOD" -o jsonpath='{range .spec.containers[0].env[*]}{.name}{" <- "}{.valueFrom.secretKeyRef.name}{"/"}{.valueFrom.secretKeyRef.key}{"\n"}{end}' 2>&1 | grep -avi memcache | grep -iE 'ADMIN|BOOTSTRAP'
echo "=== candidate secrets ==="
kubectl -n "$GWNS" get secret 2>&1 | grep -avi memcache | grep -iE 'keycloak|admin' | head
echo DONE
