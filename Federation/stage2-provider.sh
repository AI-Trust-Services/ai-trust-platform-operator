#!/bin/bash
# Stage 2 — register the FEDERATED "AI Trust Platform (on ai-trust-1)" provider on PROD's kcp.
# Additive: a NEW provider workspace root:providers:ai-trust-remote + APIExport sub.aitrust.remote +
# ProviderMetadata + ContentConfiguration (points at a prod-side nginx tile). Does NOT touch the
# existing prod-local provider (root:providers:ai-trust / sub.aitrust.msp). The workload behind this
# APIExport is the Stage-3 federation controller (deployed later) — until then the tile shows but the
# subscriptions resource is not yet published (expected).
set -uo pipefail
FED="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUNDLE="/mnt/c/Claude/projects/eu-ai-trust-prod/Standard_AiTrust_MT_MSP"   # PROD bundle (kcp = prod)
source "$BUNDLE/scripts/lib.sh"; load_config
f(){ grep -avi memcache; }

REMOTE_WS="root:providers:ai-trust-remote"
REMOTE_EXPORT="sub.aitrust.remote"
REMOTE_NS="aitrust-remote"

echo "=== 0. shoot + kcp access (PROD) ==="
[ -s "$SHOOT_KUBECONFIG" ] || mint_shoot_kubeconfig
setup_kcp; kcp_portforward
trap 'pkill -f "port-forward.*root-proxy.*6443" 2>/dev/null || true' EXIT

echo "=== 1. prod-side federated tile nginx (ns $REMOTE_NS) ==="
sk create namespace "$REMOTE_NS" --dry-run=client -o yaml 2>/dev/null | sk apply -f - 2>&1 | f
# ConfigMap from the reviewed tile JSON
sk -n "$REMOTE_NS" create configmap aitrust-remote-tile \
  --from-file=pm-content.json="$FED/stage2-remote-tile.json" --dry-run=client -o yaml 2>/dev/null \
  | sk apply -f - 2>&1 | f
sk apply -f "$FED/stage2-remote-portal.yaml" 2>&1 | f
KUBECONFIG="$SHOOT_KUBECONFIG" kubectl -n "$REMOTE_NS" rollout status deploy/aitrust-remote-portal --timeout=120s 2>&1 | f

echo "=== 2. provider workspace $REMOTE_WS (idempotent) ==="
PARENT="${REMOTE_WS%:*}"; WSNAME="${REMOTE_WS##*:}"   # root:providers , ai-trust-remote
kc "$PARENT" get workspace "$WSNAME" >/dev/null 2>&1 || {
  kc root get workspace providers >/dev/null 2>&1 || cat <<'EOF' | kc root apply --validate=false -f - >/dev/null 2>&1
apiVersion: tenancy.kcp.io/v1alpha1
kind: Workspace
metadata: { name: providers }
spec: { type: { name: providers, path: root } }
EOF
  echo "  creating provider workspace $REMOTE_WS…"
  cat <<EOF | kc "$PARENT" apply --validate=false -f - 2>&1 | f
apiVersion: tenancy.kcp.io/v1alpha1
kind: Workspace
metadata: { name: ${WSNAME} }
spec: { type: { name: provider, path: root } }
EOF
  for i in $(seq 1 36); do
    kc "$PARENT" get workspace "$WSNAME" -o jsonpath='{.status.phase}' 2>/dev/null | grep -qx Ready && break; sleep 5
  done
}
echo "  workspace phase: $(kc "$PARENT" get workspace "$WSNAME" -o jsonpath='{.status.phase}' 2>&1 | f)"

echo "=== 3. install aitrust-pm (federated values) INTO $REMOTE_WS ==="
ws_kubeconfig "$REMOTE_WS" "$BUNDLE/.state/ws-aitrust-remote.kubeconfig"
helm --kubeconfig "$BUNDLE/.state/ws-aitrust-remote.kubeconfig" upgrade -i aitrust-pm-remote \
  "$BUNDLE/charts/aitrust-pm-app" --namespace aitrust-remote --create-namespace \
  -f "$FED/stage2-pm-remote-values.yaml" 2>&1 | f | tail -3

echo "=== 4. bind system:authenticated so portal users can Enable ==="
bind_authenticated "$REMOTE_WS"

echo "=== 5. verify kcp objects present in $REMOTE_WS ==="
echo "  APIExport:          $(kc "$REMOTE_WS" get apiexport "$REMOTE_EXPORT" -o name 2>&1 | f)"
echo "  ProviderMetadata:   $(kc "$REMOTE_WS" get providermetadata "$REMOTE_EXPORT" -o name 2>&1 | f)"
echo "  ContentConfiguration: $(kc "$REMOTE_WS" get contentconfiguration aitrust-ui -o name 2>&1 | f)"
echo "  tile reachable in-cluster:"
sk -n "$REMOTE_NS" get deploy aitrust-remote-portal 2>&1 | f
echo "=== 6. confirm the prod-LOCAL provider is untouched ==="
echo "  local APIExport: $(kc root:providers:ai-trust get apiexport sub.aitrust.msp -o name 2>&1 | f)"
echo "DONE_STAGE2"
