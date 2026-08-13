#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config >/dev/null 2>&1
export KUBECONFIG="$SHOOT_KUBECONFIG"
GWNS=platform-mesh-system
echo "=== query OpenFGA API directly: list stores (from inside a pod that can reach openfga) ==="
kubectl -n $GWNS exec deploy/iam-service -- sh -lc 'wget -qO- http://openfga:8080/stores 2>/dev/null || curl -s http://openfga:8080/stores' 2>&1 | grep -avi memcache | head -40
echo
echo "=== authz model for aitrustmt store (types present) — via openfga API ==="
kubectl -n $GWNS exec deploy/iam-service -- sh -lc 'wget -qO- http://openfga:8080/stores/01KZVNHGWP27BANHPKTB3RNWEB/authorization-models 2>/dev/null' 2>&1 | grep -avi memcache | python3 -c "import sys,json; d=json.load(sys.stdin); m=d['authorization_models'][0]; print('MODEL id:',m['id']); print('TYPES:',[t['type'] for t in m['type_definitions']])" 2>&1 | head
echo
echo "=== iam-service API endpoints (GraphQL? REST?) — probe root + openapi ==="
kubectl -n $GWNS exec deploy/iam-service -- sh -lc 'wget -qO- http://localhost:8080/ 2>/dev/null | head -c 400; echo; wget -qO- http://localhost:8080/openapi.json 2>/dev/null | head -c 200' 2>&1 | grep -avi memcache | head -20
