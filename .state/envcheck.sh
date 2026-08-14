#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
echo "=== registry backend env names (tenancy-related) ==="
kubectl -n "$NS" get deploy ai-system-registry-backend -o jsonpath='{range .spec.template.spec.containers[0].env[*]}{.name}={.value}{"\n"}{end}' 2>&1 | grep -avi memcache | grep -iE 'TENAN|OPENFGA_STORE|KEYCLOAK_URL' | head -20
echo "=== envFrom (configMapRef?) ==="
kubectl -n "$NS" get deploy ai-system-registry-backend -o jsonpath='{.spec.template.spec.containers[0].envFrom}{"\n"}' 2>&1 | grep -avi memcache
echo "=== does the pod actually resolve tenancy? (import + MODE) ==="
kubectl -n "$NS" exec deploy/ai-system-registry-backend -- sh -lc 'python -c "from ai_trust_tenancy.config import MODE; print(\"resolver MODE=\", MODE)"' 2>&1 | grep -avi memcache | head
echo DONE
