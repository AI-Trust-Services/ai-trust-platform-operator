#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp; GWNS=platform-mesh-system
echo "=== copy mesh keycloak-admin secret into $NS as mesh-keycloak-admin ==="
U=$(kubectl -n "$GWNS" get secret keycloak-admin -o jsonpath='{.data.username}' 2>/dev/null | grep -avi memcache)
P=$(kubectl -n "$GWNS" get secret keycloak-admin -o jsonpath='{.data.password}' 2>/dev/null | grep -avi memcache)
[ -n "$U" ] && [ -n "$P" ] || { echo "FAILED to read mesh admin secret"; exit 1; }
cat <<EOF | kubectl apply -f - 2>&1 | grep -avi memcache
apiVersion: v1
kind: Secret
metadata: { name: mesh-keycloak-admin, namespace: $NS, labels: { app.kubernetes.io/managed-by: aitrust-mt-operator } }
type: Opaque
data:
  username: $U
  password: $P
EOF
echo "copied (username/password present: $([ -n "$U" ] && echo yes))"
echo DONE
