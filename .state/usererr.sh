#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
echo "=== users-backend recent logs (the 500s) ==="
kubectl -n "$NS" logs deploy/users-backend --tail=60 2>&1 | grep -avi memcache | grep -viE 'GET /health|/ping' | tail -40
echo "=== users-backend KEYCLOAK/TENANCY env ==="
kubectl -n "$NS" get deploy users-backend -o jsonpath='{range .spec.template.spec.containers[0].env[*]}{.name}={.value}{"\n"}{end}' 2>&1 | grep -avi memcache | grep -iE 'KEYCLOAK|TENANCY|TENANT|OPENFGA|DATABASE'
echo DONE
