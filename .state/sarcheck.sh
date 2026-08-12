#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
setup_kcp; kcp_portforward
trap 'pkill -f "port-forward.*root-proxy.*6443" 2>/dev/null || true' EXIT
WS=root:orgs:mirceatest3:accounttest
echo "=== can the user create the CR? (SAR as the user) ==="
kc "$WS" create -o yaml -f - 2>/dev/null <<EOF | grep -av memcache | grep -iE 'allowed|reason'
apiVersion: authorization.k8s.io/v1
kind: SubjectAccessReview
spec:
  user: mircea.craciun@sap.com
  resourceAttributes: { verb: create, group: trust.ai-trust.msp, resource: aitrustplatforminstances, version: v1alpha1, namespace: default }
EOF
echo "=== can a namespaced-admin create it? try creating one AS the user in default ns ==="
kc "$WS" -n default create --as=mircea.craciun@sap.com -f - 2>&1 <<EOF | grep -av memcache | head -5
apiVersion: trust.ai-trust.msp/v1alpha1
kind: AITrustPlatformInstance
metadata: { name: probe-create }
spec: { displayName: probe, sizeClass: small }
EOF
echo "=== the APIExport maximalPermissionPolicy (does it delegate create to consumers?) ==="
kc "$PROVIDER_WS" get apiexport "$EXPORT_NAME" -o jsonpath='{.spec.maximalPermissionPolicy}{"\n"}' 2>&1 | grep -av memcache
echo "=== working private-llm APIExport maximalPermissionPolicy for comparison ==="
kc root:providers:private-llm get apiexport llm.privatellms.msp -o jsonpath='{.spec.maximalPermissionPolicy}{"\n"}' 2>&1 | grep -av memcache
