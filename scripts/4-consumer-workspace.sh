#!/bin/bash
# 4-consumer-workspace.sh — org Account + child Account + default ns, with the tutorial's
# SAR-poll + Store-wait + rebac-authz-webhook roll + bounded retry. (Ported from Standard_MSP_Demo.)
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; source "$HERE/lib.sh"; load_config
[ -s "$SHOOT_KUBECONFIG" ] || mint_shoot_kubeconfig
setup_kcp; kcp_portforward
trap 'pkill -f "port-forward.*root-proxy.*6443" 2>/dev/null || true' EXIT

roll_webhook(){
  sk -n "$MESH_NS" rollout restart deployment/rebac-authz-webhook >/dev/null 2>&1 || true
  sk -n "$MESH_NS" rollout status deployment/rebac-authz-webhook --timeout=90s >/dev/null 2>&1 || true
}
sar_ok(){ local ws="$1"
  kc "$ws" create -o yaml -f - 2>/dev/null <<EOF | grep -q 'allowed: true'
apiVersion: authorization.k8s.io/v1
kind: SubjectAccessReview
spec:
  user: ${DEMO_USER}
  resourceAttributes: { verb: create, group: core.platform-mesh.io, resource: accounts, version: v1alpha1 }
EOF
}
poll_sar(){ local ws="$1"; for a in 1 2 3; do for _ in $(seq 1 30); do sar_ok "$ws" && return 0; sleep 2; done; roll_webhook; done; return 1; }

if kc root:orgs get workspace "$ORG_NAME" >/dev/null 2>&1; then
  ok "org workspace root:orgs:$ORG_NAME already exists"
else
  log "Waiting for authorization to create Accounts in root:orgs…"
  poll_sar root:orgs || die "SAR never allowed Account create in root:orgs (webhook stuck?)"
  log "Creating org Account '$ORG_NAME'…"
  kc root:orgs create --as="$DEMO_USER" -f - <<EOF >/dev/null 2>&1
apiVersion: core.platform-mesh.io/v1alpha1
kind: Account
metadata: { name: ${ORG_NAME} }
spec: { type: org, displayName: "AI Trust Demo Org" }
EOF
  orgready(){ kc root:orgs get account "$ORG_NAME" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -qx True; }
  wait_for 180 5 "org Account $ORG_NAME Ready" orgready
fi

storeok(){ kc root:orgs get store "$ORG_NAME" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -qx True; }
wait_for 180 5 "org Store $ORG_NAME Ready" storeok || warn "store not confirmed Ready (continuing)"
roll_webhook

if kc "root:orgs:$ORG_NAME" get workspace "$ACCOUNT_NAME" >/dev/null 2>&1; then
  ok "account workspace root:orgs:$ORG_NAME:$ACCOUNT_NAME already exists"
else
  log "Waiting for authorization to create Accounts in root:orgs:$ORG_NAME…"
  poll_sar "root:orgs:$ORG_NAME" || die "SAR never allowed Account create in root:orgs:$ORG_NAME"
  log "Creating child Account '$ACCOUNT_NAME'…"
  kc "root:orgs:$ORG_NAME" create --as="$DEMO_USER" -f - <<EOF >/dev/null 2>&1
apiVersion: core.platform-mesh.io/v1alpha1
kind: Account
metadata: { name: ${ACCOUNT_NAME} }
spec: { type: account, displayName: "AI Trust Tenant" }
EOF
  acctready(){ kc "root:orgs:$ORG_NAME" get account "$ACCOUNT_NAME" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -qx True; }
  wait_for 180 5 "child Account $ACCOUNT_NAME Ready" acctready
fi

WS="root:orgs:$ORG_NAME:$ACCOUNT_NAME"
kc "$WS" create namespace default --dry-run=client -o yaml | kc "$WS" apply -f - >/dev/null 2>&1 || true
ok "consumer workspace ready → $WS"
