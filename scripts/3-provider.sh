#!/bin/bash
# 3-provider.sh — register the AI Trust Platform provider on the mesh.
#   1) provider workspace $PROVIDER_WS (root:providers:ai-trust)
#   2) PM chart INTO that workspace FIRST (creates APIExport + APIExportEndpointSlice + CC + RBAC) —
#      the syncagent needs the EndpointSlice at startup, else it crash-loops.
#   3) workload chart on the shoot (MT operator + syncagent + portal nginx), operator image pinned.
#   4) syncagent hostAlias fix + bind_authenticated.
#   5) wait until the APIExport publishes subscriptions.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; source "$HERE/lib.sh"; load_config
[ -s "$SHOOT_KUBECONFIG" ] || mint_shoot_kubeconfig
setup_kcp; kcp_portforward
trap 'pkill -f "port-forward.*root-proxy.*6443" 2>/dev/null || true' EXIT

# 1. provider workspace (idempotent). PROVIDER_WS = root:providers:ai-trust
PARENT="${PROVIDER_WS%:*}"; WSNAME="${PROVIDER_WS##*:}"     # root:providers , ai-trust
kc "$PARENT" get workspace "$WSNAME" >/dev/null 2>&1 || {
  kc root get workspace providers >/dev/null 2>&1 || cat <<'EOF' | kc root apply --validate=false -f - >/dev/null
apiVersion: tenancy.kcp.io/v1alpha1
kind: Workspace
metadata: { name: providers }
spec: { type: { name: providers, path: root } }
EOF
  log "Creating provider workspace $PROVIDER_WS…"
  cat <<EOF | kc "$PARENT" apply --validate=false -f - >/dev/null
apiVersion: tenancy.kcp.io/v1alpha1
kind: Workspace
metadata: { name: ${WSNAME} }
spec: { type: { name: provider, path: root } }
EOF
  wsok(){ kc "$PARENT" get workspace "$WSNAME" -o jsonpath='{.status.phase}' 2>/dev/null | grep -qx Ready; }
  wait_for 180 5 "provider workspace $PROVIDER_WS Ready" wsok
}

# 2. PM chart INTO the provider workspace (host-side helm via root-proxy port-forward).
log "Installing aitrust-pm into $PROVIDER_WS…"
ws_kubeconfig "$PROVIDER_WS" "$STATE/ws-aitrust.kubeconfig"
helm --kubeconfig "$STATE/ws-aitrust.kubeconfig" upgrade -i aitrust-pm "$HERE/../$AITRUST_PM_CHART" \
  --namespace aitrust --create-namespace \
  --set exportName="$EXPORT_NAME" \
  --set content.publicScheme="$CONTENT_SCHEME" \
  --set content.publicHost="$AITRUST_CONTENT_HOST" \
  >/dev/null 2>&1 || warn "aitrust-pm helm returned non-zero — check the provider workspace"
exportok(){ kc "$PROVIDER_WS" get apiexport "$EXPORT_NAME" >/dev/null 2>&1; }
wait_for 120 5 "APIExport $EXPORT_NAME present in $PROVIDER_WS" exportok
ok "aitrust-pm installed (APIExport + ContentConfiguration + ProviderMetadata + bind RBAC)"

# 3. workload chart on the shoot (MT operator + syncagent + portal nginx). Embed the kcp-admin kubeconfig,
#    rewriting its server to the provider workspace + :8443 so the syncagent syncs from the right ws.
log "Installing aitrust-app (workload) on the shoot into ns $PROVIDER_NS…"
# build an adminContent kubeconfig whose server points at the provider workspace over the in-cluster :8443.
# ALSO strip the CA + tls-server-name and set insecure-skip-tls-verify: the syncagent's sync controller
# dials the APIExport virtual-workspace advertised as https://root.kcp.localhost:8443/... but the mesh cert
# is valid for frontproxy/kcp.api.<domain>, NOT root.kcp.localhost → x509 verify fails. Skipping verify
# (client cert still authenticates) is the proven fix (see Standard_MSP_Demo/msp_demo_howto.md).
KC_WS="$STATE/kcp-provider-incluster.yaml"
cp "$KCP_ADMIN_RAW" "$KC_WS"
python3 - "$KC_WS" "$KCP_INCLUSTER_URL/clusters/$PROVIDER_WS" <<'PY'
import sys, re
p, server = sys.argv[1], sys.argv[2]
lines = open(p).read().splitlines()
out = []
for ln in lines:
    if 'certificate-authority-data:' in ln or 'tls-server-name:' in ln:
        continue
    if re.match(r'\s*server: https://', ln):
        indent = ln[:len(ln)-len(ln.lstrip())]
        out.append(f'{indent}server: {server}')
        out.append(f'{indent}insecure-skip-tls-verify: true')
        continue
    out.append(ln)
open(p, 'w').write('\n'.join(out) + '\n')
PY
# Pre-install the api-syncagent PublishedResource CRD BEFORE the aitrust-app chart. The chart ships a
# PublishedResource CR (publish-aitrust-subscriptions); on a FRESH mesh the syncagent.kcp.io CRD does
# not exist yet (the syncagent binary would install it on startup, but Helm validates the CR at apply
# time and fails the whole atomic release: "no matches for kind PublishedResource"). Bundled at
# ../crds; fall back to the upstream pinned tag if absent. Idempotent.
CRD_LOCAL="$HERE/../charts/aitrust-app/crds/publishedresources.syncagent.kcp.io.yaml"
if sk get crd publishedresources.syncagent.kcp.io >/dev/null 2>&1; then
  ok "syncagent PublishedResource CRD already present"
elif [ -f "$CRD_LOCAL" ]; then
  sk apply -f "$CRD_LOCAL" >/dev/null && ok "installed bundled syncagent PublishedResource CRD"
else
  SA_REF="v0.5.1"
  curl -fsSL "https://raw.githubusercontent.com/kcp-dev/api-syncagent/${SA_REF}/deploy/crd/kcp.io/syncagent.kcp.io_publishedresources.yaml" \
    | sk apply -f - >/dev/null && ok "installed syncagent CRD from upstream ${SA_REF}" \
    || die "could not install the syncagent PublishedResource CRD (bundle ../crds missing + upstream fetch failed)"
fi
helm --kubeconfig "$SHOOT_KUBECONFIG" upgrade -i aitrust-app "$HERE/../$AITRUST_APP_CHART" \
  --namespace "$PROVIDER_NS" --create-namespace \
  --set operator.image.repository="$OPERATOR_IMAGE" \
  --set operator.image.tag="$OPERATOR_TAG" \
  --set operator.instanceDomainSuffix="$INSTANCE_DOMAIN_SUFFIX" \
  --set operator.registry="$REGISTRY" \
  --set operator.tag="$TAG" \
  --set operator.mspWorkerLabel="$MSP_WORKER_LABEL" \
  --set operator.federationMode="${FEDERATION_MODE:-local}" \
  --set kcpKubeconfig.inClusterServerUrl="$KCP_INCLUSTER_URL" \
  --set-file kcpKubeconfig.adminContent="$KC_WS" \
  || die "aitrust-app helm install FAILED (see error above) — inspect: helm --kubeconfig \$SHOOT_KUBECONFIG get manifest -n $PROVIDER_NS aitrust-app"
ok "workload chart installed (MT operator + syncagent + portal nginx in $PROVIDER_NS)"

# 4. syncagent hostAlias + bind authenticated.
patch_syncagent_hostalias "$PROVIDER_NS" aitrust-syncagent
bind_authenticated "$PROVIDER_WS"

# 5. wait until the APIExport publishes the CR.
log "Waiting for APIExport $EXPORT_NAME to publish subscriptions…"
have_res(){ kc "$PROVIDER_WS" get apiexport "$EXPORT_NAME" \
  -o jsonpath='{range .spec.resources[*]}{.name}{"\n"}{end}' 2>/dev/null | grep -q '^subscriptions$'; }
wait_for 300 10 "APIExport has subscriptions" have_res || warn "resource not yet published — check syncagent logs"
ok "AI Trust Platform provider ready"
