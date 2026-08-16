#!/bin/bash
# lib.sh — shared helpers for the AI Trust Platform MSP provider deploy (targets shoot ai-trust-1).
# Reuses the Standard_MSP_Demo mesh helpers (kc, ws_kubeconfig, patch_syncagent_hostalias,
# bind_authenticated, mint, kcp_portforward) + a render() for the ingress templates.
# All identifiers come from prerequisites/config.env (MT model: ONE shared app + per-tenant Subscriptions).
export PATH="$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUNDLE="$(cd "$LIB_DIR/.." && pwd)"
PREREQ="$BUNDLE/prerequisites"
CONFIG="$BUNDLE/config"
STATE="$BUNDLE/.state"; mkdir -p "$STATE"

c_reset=$'\033[0m'; c_red=$'\033[31m'; c_grn=$'\033[32m'; c_yel=$'\033[33m'; c_blu=$'\033[36m'
log(){ echo "${c_blu}==>${c_reset} $*"; }
ok(){ echo "${c_grn}✅ $*${c_reset}"; }
warn(){ echo "${c_yel}⚠️  $*${c_reset}"; }
err(){ echo "${c_red}❌ $*${c_reset}" >&2; }
die(){ err "$*"; exit 1; }

load_config(){
  [ -f "$PREREQ/config.env" ] || die "Missing $PREREQ/config.env"
  set -a; source "$PREREQ/config.env"; set +a
  : "${MESH_NS:=platform-mesh-system}"
  : "${GATEWAY_NS:=platform-mesh-system}"; : "${GATEWAY_NAME:=k8sapi-gateway}"
  : "${WORKER_POOL:=ai-trust}"; : "${WORKER_ZONE:=eu-de-1b}"; : "${WORKER_MIN:=1}"; : "${WORKER_MAX:=4}"
  : "${WORKER_TYPE:=m_c16_m128_v2}"
  : "${WORKER_IMAGE_VERSION:=}"; : "${MSP_WORKER_LABEL:=ai-trust}"
  : "${KCP_INCLUSTER_URL:=https://frontproxy-front-proxy.platform-mesh-system.svc.cluster.local:8443}"
  : "${PROVIDER_WS:=root:providers:ai-trust}"; : "${EXPORT_NAME:=sub.aitrust.msp}"
  : "${PROVIDER_NS:=aitrust-msp}"; : "${CONTENT_SCHEME:=http}"
  : "${AITRUST_CONTENT_HOST:=aitrust-portal.aitrust-msp.svc.cluster.local}"
  : "${AITRUST_APP_CHART:=charts/aitrust-app}"; : "${AITRUST_PM_CHART:=charts/aitrust-pm-app}"
  : "${OPERATOR_IMAGE:=mirceacraciun795/aitrust-operator}"; : "${OPERATOR_TAG:=v1}"
  : "${REGISTRY:=mirceacraciun795}"; : "${TAG:=aitrust}"
  : "${SHARED_APP_HOST:=ai-trust.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu}"
  : "${ORG_NAME:=aitrust}"; : "${ACCOUNT_NAME:=tenant}"; : "${INSTANCE_NAME:=my-subscription}"; : "${INSTANCE_PLAN:=standard}"
  [ "${SHOOT_NAME:-}" = "ai-trust-1" ] || die "SHOOT_NAME is '${SHOOT_NAME:-}' — this bundle only targets ai-trust-1."
  export SHOOT_NAME PROJECT GARDENER_API MESH_NS GATEWAY_NS GATEWAY_NAME KCP_INCLUSTER_URL
  export WORKER_TYPE WORKER_POOL WORKER_ZONE WORKER_MIN WORKER_MAX WORKER_IMAGE_VERSION MSP_WORKER_LABEL
  export PROVIDER_WS EXPORT_NAME PROVIDER_NS AITRUST_APP_CHART AITRUST_PM_CHART
  export OPERATOR_IMAGE OPERATOR_TAG REGISTRY TAG INSTANCE_DOMAIN_SUFFIX SHARED_APP_HOST
  export CONTENT_SCHEME AITRUST_CONTENT_HOST DEMO_USER ORG_NAME ACCOUNT_NAME INSTANCE_NAME INSTANCE_PLAN
}

GARDEN_KUBECONFIG="$PREREQ/garden-kubeconfig.yaml"
garden(){ kubectl --kubeconfig "$GARDEN_KUBECONFIG" "$@"; }

SHOOT_KUBECONFIG="$STATE/shoot-kubeconfig.yaml"
mint_shoot_kubeconfig(){
  log "Minting shoot admin kubeconfig for '$SHOOT_NAME'…"
  local resp
  resp="$(garden create -f - --raw "/apis/core.gardener.cloud/v1beta1/namespaces/${PROJECT}/shoots/${SHOOT_NAME}/adminkubeconfig" <<< \
    '{"apiVersion":"authentication.gardener.cloud/v1alpha1","kind":"AdminKubeconfigRequest","spec":{"expirationSeconds":14400}}' 2>&1)" \
    || die "adminkubeconfig failed (fresh garden login? run prerequisites/login.sh):\n$resp"
  echo "$resp" | jq -r '.status.kubeconfig' | base64 -d > "$SHOOT_KUBECONFIG"
  [ -s "$SHOOT_KUBECONFIG" ] || die "minted kubeconfig empty"
  ok "shoot kubeconfig → $SHOOT_KUBECONFIG"
}
sk(){ [ -s "$SHOOT_KUBECONFIG" ] || mint_shoot_kubeconfig; kubectl --kubeconfig "$SHOOT_KUBECONFIG" "$@"; }

# --- kcp access (identical mechanism to Standard_MSP_Demo) ------------------
KCP_ADMIN_RAW="$STATE/kcp-admin-raw.yaml"
KCP_KUBECONFIG="$STATE/kcp-admin.kubeconfig"
KCP_HOST=""
setup_kcp(){
  sk -n "$MESH_NS" get secret kubeconfig-kcp-admin -o jsonpath='{.data.kubeconfig}' | base64 -d > "$KCP_ADMIN_RAW" \
    || die "could not read kubeconfig-kcp-admin — is the mesh Ready?"
  cp "$KCP_ADMIN_RAW" "$KCP_KUBECONFIG"
  sed -i '/certificate-authority-data:/d; /tls-server-name:/d' "$KCP_KUBECONFIG" 2>/dev/null || true
  KCP_HOST="$(grep -oE 'server: https://[^/]+' "$KCP_ADMIN_RAW" | head -1 | sed -E 's|server: https://([^:]+).*|\1|')"
  : "${KCP_HOST:=kcp.api.portal.localhost}"; export KCP_HOST
}
kc(){ local ws="$1"; shift; KUBECONFIG="$KCP_KUBECONFIG" kubectl --insecure-skip-tls-verify \
      --server "https://127.0.0.1:6443/clusters/${ws}" "$@"; }
kcp_portforward(){
  pkill -f "port-forward.*root-proxy.*6443" 2>/dev/null || true; sleep 1
  sk -n "$MESH_NS" port-forward svc/root-proxy 6443:6443 >/tmp/pf-kcp-aitrust.log 2>&1 &
  sleep 4
}
ws_kubeconfig(){
  local ws="$1" out="$2"
  [ -s "$KCP_ADMIN_RAW" ] || setup_kcp
  local CERT KEY
  CERT="$(KUBECONFIG="$KCP_ADMIN_RAW" kubectl config view --raw -o jsonpath='{.users[0].user.client-certificate-data}')"
  KEY="$(KUBECONFIG="$KCP_ADMIN_RAW" kubectl config view --raw -o jsonpath='{.users[0].user.client-key-data}')"
  cat > "$out" <<EOF
apiVersion: v1
kind: Config
current-context: c
clusters:
- name: w
  cluster:
    server: https://127.0.0.1:6443/clusters/${ws}
    insecure-skip-tls-verify: true
contexts:
- name: c
  context: { cluster: w, user: u }
users:
- name: u
  user:
    client-certificate-data: ${CERT}
    client-key-data: ${KEY}
EOF
}

# syncagent hostAlias fix (root.kcp.localhost → frontproxy ClusterIP). Call AFTER the PM chart.
patch_syncagent_hostalias(){
  local ns="$1" fallback="${2:-}"
  local fpip; fpip="$(sk -n "$MESH_NS" get svc frontproxy-front-proxy -o jsonpath='{.spec.clusterIP}' 2>/dev/null)"
  [ -n "$fpip" ] || { warn "frontproxy ClusterIP not found — skipping hostAlias"; return 0; }
  local target=""
  for d in $(sk -n "$ns" get deploy -o name 2>/dev/null); do
    if sk -n "$ns" get "$d" -o jsonpath='{.spec.template.spec.containers[*].image}' 2>/dev/null | grep -qi 'api-syncagent'; then
      target="$d"; break
    fi
  done
  [ -n "$target" ] || target="deployment/${fallback}"
  sk -n "$ns" get "$target" >/dev/null 2>&1 || { warn "syncagent deploy not found in $ns"; return 0; }
  # merge-patch (idempotent): sets hostAliases whether or not the field already exists. A json `add`
  # to /spec/template/spec/hostAliases FAILS if the array is already present (re-run / pre-existing) —
  # that previously left the syncagent unable to resolve root.kcp.localhost → sync stalled silently.
  sk -n "$ns" patch "$target" --type=merge -p \
    "{\"spec\":{\"template\":{\"spec\":{\"hostAliases\":[{\"ip\":\"$fpip\",\"hostnames\":[\"root.kcp.localhost\",\"${KCP_HOST}\"]}]}}}}" >/dev/null 2>&1 \
    && ok "hostAlias root.kcp.localhost,${KCP_HOST} → $fpip on $ns/$target" \
    || warn "hostAlias patch on $ns/$target returned non-zero"
  sk -n "$ns" rollout restart "$target" >/dev/null 2>&1 || true
  KUBECONFIG="$SHOOT_KUBECONFIG" kubectl -n "$ns" rollout status "$target" --timeout=150s >/dev/null 2>&1 || true
}

wait_for(){ local t=$1 i=$2 d=$3; shift 3; local w=0; log "Waiting: $d (timeout ${t}s)"
  while ! "$@" >/dev/null 2>&1; do sleep "$i"; w=$((w+i)); [ "$w" -ge "$t" ] && { err "timeout: $d"; return 1; }; printf '.'; done; echo; ok "$d"; }

# bind_authenticated <provider-ws> — let system:authenticated portal users Enable (belt-and-suspenders;
# the pm chart already ships this, but re-applying is harmless + covers a pre-existing export).
bind_authenticated(){
  local ws="$1"
  cat <<'EOF' | kc "$ws" apply -f - >/dev/null 2>&1 \
    && ok "apiexport-bind → system:authenticated in $ws" \
    || warn "apiexport-bind-authenticated apply in $ws returned non-zero (may already exist)"
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: apiexport-bind-authenticated
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: apiexport-bind
subjects:
  - apiGroup: rbac.authorization.k8s.io
    kind: Group
    name: system:authenticated
EOF
}

# render() — substitute placeholders in the ingress templates (kept for parity with Standard_Ai_Platform,
# though the operator now creates per-instance routes itself). Used only if a script needs a static route.
render(){ sed -e "s|__APP_DOMAIN__|${APP_DOMAIN:-}|g" -e "s|__APP_URL__|${APP_URL:-}|g" \
              -e "s|__APP_NS__|${APP_NS:-}|g" "$1"; }
