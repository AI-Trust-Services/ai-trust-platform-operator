#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
POD=$(kubectl -n "$NS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep '^oauth2-proxy-' | grep Running | awk '{print $1}' | head -1)
echo "pod: $POD"
echo "=== from oauth2-proxy pod: can it reach the mesh keycloak in-cluster token endpoint? ==="
kubectl -n "$NS" exec "$POD" -- sh -lc '
wget -qO- --timeout=8 "http://keycloak-service.platform-mesh-system.svc.cluster.local:8080/keycloak/realms/poc2/.well-known/openid-configuration" 2>/dev/null | head -c 400
echo
echo "--- token_endpoint reachable? ---"
wget -qS -O /dev/null --timeout=8 "http://keycloak-service.platform-mesh-system.svc.cluster.local:8080/keycloak/realms/poc2/protocol/openid-connect/token" 2>&1 | head -3
' 2>&1 | grep -avi memcache | head -20
echo DONE
