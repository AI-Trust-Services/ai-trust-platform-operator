#!/bin/bash
# reset.sh — remove the AI Trust Platform provider + the shared app + all Subscriptions, keeping the mesh.
#   - delete Subscription CRs in the consumer ws (finalizer soft-disables the tenant realm; data retained)
#   - uninstall the workload + pm charts; delete the shared app namespace ($PROVIDER_NS, cascades everything)
#   - delete the provider workspace ($PROVIDER_WS)
#   - sweep the aitrust shared-app HTTPRoute on the gateway
#   - --pool also drops the $WORKER_POOL (ai-trust) worker pool
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; source "$HERE/lib.sh"; load_config
[ -s "$SHOOT_KUBECONFIG" ] || mint_shoot_kubeconfig
setup_kcp; kcp_portforward
trap 'pkill -f "port-forward.*root-proxy.*6443" 2>/dev/null || true' EXIT
WS="root:orgs:$ORG_NAME:$ACCOUNT_NAME"

log "Deleting Subscription CRs in $WS (finalizer soft-disables the tenant realms)…"
kc "$WS" -n default delete subscription --all --wait=false >/dev/null 2>&1 || true
sleep 10

log "Uninstalling workload chart + deleting the shared app namespace (ns $PROVIDER_NS)…"
helm --kubeconfig "$SHOOT_KUBECONFIG" -n "$PROVIDER_NS" uninstall aitrust-app >/dev/null 2>&1 || true
sk delete ns "$PROVIDER_NS" --wait=false >/dev/null 2>&1 || true

log "Uninstalling pm chart from $PROVIDER_WS…"
ws_kubeconfig "$PROVIDER_WS" "$STATE/ws-aitrust.kubeconfig"
helm --kubeconfig "$STATE/ws-aitrust.kubeconfig" uninstall aitrust-pm >/dev/null 2>&1 || true

log "Deleting provider workspace $PROVIDER_WS…"
PARENT="${PROVIDER_WS%:*}"; WSNAME="${PROVIDER_WS##*:}"
kc "$PARENT" delete workspace "$WSNAME" --wait=false >/dev/null 2>&1 || true

# Sweep the shared-app HTTPRoute (+ any leftover per-tenant routes) on the gateway.
for r in $(sk -n "$GATEWAY_NS" get httproute -o name 2>/dev/null | grep -E 'aitrust' || true); do
  sk -n "$GATEWAY_NS" delete "$r" >/dev/null 2>&1 || true
done

# Sweep CLUSTER-SCOPED leftovers that block a clean re-deploy (helm can't adopt objects owned by a
# prior release; a stale PublishedResource with the same agent-name poisons the new syncagent).
# These are cluster/kcp-scoped so `delete ns` above does NOT remove them.
log "Sweeping cluster-scoped leftovers (ClusterRoles, PublishedResources)…"
for cr in aitrust-operator aitrust-syncagent; do
  sk delete clusterrole "$cr" --ignore-not-found >/dev/null 2>&1 || true
  sk delete clusterrolebinding "$cr" --ignore-not-found >/dev/null 2>&1 || true
done
# PublishedResources selected by our syncagent's agent-name (leftover ones stall sync on missing CRDs)
for pr in $(sk get publishedresources.syncagent.kcp.io -o name 2>/dev/null | grep -E 'aitrust' || true); do
  sk delete "$pr" --ignore-not-found >/dev/null 2>&1 || true
done

if [ "${1:-}" = "--pool" ]; then
  log "Dropping worker pool $WORKER_POOL…"
  IDX="$(garden get shoot "$SHOOT_NAME" -n "$PROJECT" -o json 2>/dev/null \
    | python3 -c "import json,sys;d=json.load(sys.stdin);w=d['spec']['provider']['workers'];print(next((i for i,x in enumerate(w) if x['name']=='$WORKER_POOL'),-1))")"
  [ "$IDX" -ge 0 ] 2>/dev/null && garden patch shoot "$SHOOT_NAME" -n "$PROJECT" --type=json \
    -p "[{\"op\":\"remove\",\"path\":\"/spec/provider/workers/$IDX\"}]" || warn "pool not found"
fi

ok "reset done (mesh untouched)."
