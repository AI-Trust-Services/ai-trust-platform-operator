#!/bin/bash
# Fresh consumer org+account created AFTER all fixes, to get clean GraphQL introspection.
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
setup_kcp; kcp_portforward
trap 'pkill -f "port-forward.*root-proxy.*6443" 2>/dev/null || true' EXIT
USER=mircea.craciun@sap.com
ORG=aitrustfresh
ACCT=demo
roll(){ sk -n "$MESH_NS" rollout restart deployment/rebac-authz-webhook >/dev/null 2>&1; sk -n "$MESH_NS" rollout status deployment/rebac-authz-webhook --timeout=90s >/dev/null 2>&1; }
sar(){ kc "$1" create -o yaml -f - 2>/dev/null <<EOF | grep -q 'allowed: true'
apiVersion: authorization.k8s.io/v1
kind: SubjectAccessReview
spec: { user: ${USER}, resourceAttributes: { verb: create, group: core.platform-mesh.io, resource: accounts, version: v1alpha1 } }
EOF
}
poll(){ for a in 1 2 3; do for _ in $(seq 1 30); do sar "$1" && return 0; sleep 2; done; roll; done; return 1; }

echo "=== org $ORG ==="
kc root:orgs get workspace "$ORG" >/dev/null 2>&1 || { poll root:orgs; kc root:orgs create --as="$USER" -f - <<EOF >/dev/null 2>&1
apiVersion: core.platform-mesh.io/v1alpha1
kind: Account
metadata: { name: ${ORG} }
spec: { type: org, displayName: "AI Trust Fresh" }
EOF
}
ok(){ kc root:orgs get account "$ORG" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -qx True; }
wait_for 180 5 "org $ORG Ready" ok
sok(){ kc root:orgs get store "$ORG" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -qx True; }
wait_for 180 5 "org Store Ready" sok || true; roll

echo "=== account $ACCT ==="
kc "root:orgs:$ORG" get workspace "$ACCT" >/dev/null 2>&1 || { poll "root:orgs:$ORG"; kc "root:orgs:$ORG" create --as="$USER" -f - <<EOF >/dev/null 2>&1
apiVersion: core.platform-mesh.io/v1alpha1
kind: Account
metadata: { name: ${ACCT} }
spec: { type: account, displayName: "Demo" }
EOF
}
aok(){ kc "root:orgs:$ORG" get account "$ACCT" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -qx True; }
wait_for 180 5 "account $ACCT Ready" aok
WS="root:orgs:$ORG:$ACCT"
kc "$WS" create namespace default --dry-run=client -o yaml | kc "$WS" apply -f - >/dev/null 2>&1 || true

echo "=== bind the AI Trust API (Enable) ==="
kc "$WS" apply -f - <<EOF >/dev/null
apiVersion: apis.kcp.io/v1alpha2
kind: APIBinding
metadata: { name: aitrust-binding }
spec:
  reference: { export: { path: ${PROVIDER_WS}, name: ${EXPORT_NAME} } }
  permissionClaims:
  - {group: "", resource: secrets, verbs: ["*"], selector: {matchAll: true}, state: Accepted}
  - {group: "", resource: namespaces, verbs: ["*"], selector: {matchAll: true}, state: Accepted}
  - {group: "", resource: events, verbs: ["*"], selector: {matchAll: true}, state: Accepted}
EOF
b(){ kc "$WS" get apibinding aitrust-binding -o jsonpath='{.status.phase}' 2>/dev/null | grep -qx Bound; }
wait_for 180 5 "aitrust-binding Bound" b
echo ""
echo "======================================================================"
ok "Fresh consumer ready: $WS"
echo "   Open the portal + Create there (clean introspection):"
echo "   https://${ORG}.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu/home/accounts/${ACCT}/namespaces/default/aitrust_platform_instances"
echo "======================================================================"
