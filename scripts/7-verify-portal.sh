#!/bin/bash
# 7-verify-portal.sh — verify the provider tile is renderable AND the Subscription's tenant is Ready.
#   1) portal content: /pm-content.json served (200) + ContentConfiguration Ready in the provider ws.
#   2) subscription: status.ready=true; print the tenant login URL + realm + the portal nav location.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; source "$HERE/lib.sh"; load_config
[ -s "$SHOOT_KUBECONFIG" ] || mint_shoot_kubeconfig
setup_kcp; kcp_portforward
trap 'pkill -f "port-forward.*root-proxy.*6443" 2>/dev/null || true' EXIT
WS="root:orgs:$ORG_NAME:$ACCOUNT_NAME"

# 1. content nginx serving /pm-content.json (in-cluster probe — the exact path the reconciler uses).
log "Probing $CONTENT_SCHEME://$AITRUST_CONTENT_HOST/pm-content.json …"
code="$(sk -n "$MESH_NS" run aitrustprobe-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet -- \
  curl -sS -o /dev/null -w '%{http_code}' "$CONTENT_SCHEME://$AITRUST_CONTENT_HOST/pm-content.json" 2>/dev/null || true)"
[ "$code" = "200" ] && ok "pm-content.json served ($code)" || warn "pm-content.json probe returned '$code'"

# 2. ContentConfiguration Ready in the provider ws (portal tile).
ccready(){ kc "$PROVIDER_WS" get contentconfiguration aitrust-ui -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -qx True; }
wait_for 180 15 "ContentConfiguration aitrust-ui Ready" ccready || warn "CC not Ready yet — re-check in ~1 min"

# 3. the Subscription itself (the operator provisions the tenant realm inside the shared app, ~1-2 min).
ready(){ kc "$WS" -n default get subscription "$INSTANCE_NAME" -o jsonpath='{.status.ready}' 2>/dev/null | grep -qx true; }
wait_for 600 15 "Subscription $INSTANCE_NAME Ready (tenant realm provisioned)" ready || warn "subscription not Ready yet"
URL="$(kc "$WS" -n default get subscription "$INSTANCE_NAME" -o jsonpath='{.status.url}' 2>/dev/null)"
REALM="$(kc "$WS" -n default get subscription "$INSTANCE_NAME" -o jsonpath='{.status.realm}' 2>/dev/null)"
TID="$(kc "$WS" -n default get subscription "$INSTANCE_NAME" -o jsonpath='{.status.tenantId}' 2>/dev/null)"

echo ""
echo "======================================================================"
ok "AI Trust Platform provider live on the payload cluster"
echo "   Shared app   : https://$SHARED_APP_HOST  (ONE instance; all tenants share it)"
echo "   Tenant URL   : ${URL:-<pending>}   (routes to the shared app; tenant resolved from its realm)"
echo "   Tenant realm : ${REALM:-<pending>}   tenantId=${TID:-<pending>}"
echo "   Portal tile  : account '$ACCOUNT_NAME' → Namespaces → default → expand 'AI Trust Platform'"
echo "   (tiles are namespace-scoped: NOT on the account dashboard — see PORTAL_TILES_FINDING in Standard_MSP_Demo)"
echo "======================================================================"
