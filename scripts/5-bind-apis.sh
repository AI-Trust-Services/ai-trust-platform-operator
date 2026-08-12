#!/bin/bash
# 5-bind-apis.sh — bind the AI Trust APIExport into the consumer workspace (with permission claims).
# This is the scripted equivalent of clicking "Enable" in the portal.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; source "$HERE/lib.sh"; load_config
[ -s "$SHOOT_KUBECONFIG" ] || mint_shoot_kubeconfig
setup_kcp; kcp_portforward
trap 'pkill -f "port-forward.*root-proxy.*6443" 2>/dev/null || true' EXIT
WS="root:orgs:$ORG_NAME:$ACCOUNT_NAME"

log "Applying APIBinding (aitrust-binding) in $WS…"
kc "$WS" apply -f - <<EOF >/dev/null
apiVersion: apis.kcp.io/v1alpha2
kind: APIBinding
metadata: { name: aitrust-binding }
spec:
  reference:
    export: { path: ${PROVIDER_WS}, name: ${EXPORT_NAME} }
  permissionClaims:
  - {group: "", resource: secrets,    verbs: ["*"], selector: {matchAll: true}, state: Accepted}
  - {group: "", resource: namespaces, verbs: ["*"], selector: {matchAll: true}, state: Accepted}
  - {group: "", resource: events,     verbs: ["*"], selector: {matchAll: true}, state: Accepted}
EOF

bound(){ kc "$WS" get apibinding aitrust-binding -o jsonpath='{.status.phase}' 2>/dev/null | grep -qx Bound; }
wait_for 180 5 "aitrust-binding Bound" bound
have_cr(){ kc "$WS" api-resources --api-group="$EXPORT_NAME" 2>/dev/null | grep -q '^aitrustplatforminstances'; }
wait_for 120 5 "aitrustplatforminstances API available in $WS" have_cr
ok "AI Trust API bound + served in the consumer workspace"
