#!/bin/bash
# ============================================================================
#  install.sh — unified installer for the AI Trust Platform MSP provider.
#
#  Asks ONE question: single-cluster only, or ALSO expose the provider as a
#  FEDERATED tile on a second (consumer) cluster's Marketplace.
#
#    * single-cluster  → runs scripts/deploy.sh (app + Platform Mesh on ONE shoot,
#                        the provider cluster). This is the standard install.
#    * federated       → ALSO runs the Federation flow so a SECOND cluster's portal
#                        can Enable the provider (provisioning lands on the provider
#                        cluster over its shoot API; SSO brokered). Additive — the
#                        single-cluster install is unchanged.
#
#  Federation is CROSS-cluster only. It does NOT mean "app and Platform Mesh on
#  different clusters" — the app + its own mesh always sit together on the provider
#  shoot. Federation adds a REMOTE CONSUMER cluster that offers the tile. If you
#  answer "no", you get exactly today's single-cluster deployment.
#
#  Usage:  MSYS_NO_PATHCONV=1 wsl.exe -d Ubuntu -- bash '<bundle>/install.sh'
#          (non-interactive: set MODE=single|federated + the *_KUBECONFIG vars)
# ============================================================================
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FED="$HERE/Federation"
f(){ grep -avi memcache; }
c_blu=$'\033[36m'; c_grn=$'\033[32m'; c_yel=$'\033[33m'; c_rst=$'\033[0m'
say(){ echo "${c_blu}==>${c_rst} $*"; }
ok(){  echo "${c_grn}OK${c_rst} $*"; }

echo ""
echo "######################################################################"
echo "#  AI Trust Platform installer"
echo "######################################################################"
echo ""
echo "  The AI Trust Platform runs as ONE shared multi-tenant app alongside its"
echo "  own Platform Mesh on a single 'provider' cluster (default: ai-trust-1)."
echo ""
echo "  FEDERATION (optional) additionally publishes this provider as a tile on a"
echo "  SECOND 'consumer' cluster's Marketplace. Enabling that tile provisions an"
echo "  isolated tenant back on the provider cluster (over its shoot API) and"
echo "  brokers the consumer's identity in for SSO. It is purely additive."
echo ""

# ---- choose mode (prompt unless MODE is preset) ----------------------------
MODE="${MODE:-}"
if [ -z "$MODE" ]; then
  echo "  Install mode:"
  echo "    1) single-cluster only        (app + mesh on the provider cluster)"
  echo "    2) single-cluster + FEDERATED  (also offer the tile on a 2nd cluster)"
  printf "  Choose [1/2]: "
  read -r ans
  case "$ans" in
    2) MODE="federated" ;;
    *) MODE="single" ;;
  esac
fi
say "mode = $MODE"

# ---- 1. the standard single-cluster install (always) -----------------------
say "Running the single-cluster provider install (scripts/deploy.sh)…"
bash "$HERE/scripts/deploy.sh"
ok "single-cluster provider install complete."

[ "$MODE" = "single" ] && { echo ""; ok "DONE (single-cluster). Re-run with mode 2 to add federation later."; exit 0; }

# ---- 2. federation (only if chosen) ----------------------------------------
echo ""
say "Federation selected — publishing the provider as a tile on a CONSUMER cluster."
echo "  NOTE: the federation stage scripts (stage2/stage3) currently target the documented"
echo "  ai-trust-1 (provider) → ai-trust-prod (consumer) topology: they source the consumer"
echo "  bundle at C:/Claude/projects/eu-ai-trust-prod/Standard_AiTrust_MT_MSP for the consumer's"
echo "  kcp/mesh access. For a DIFFERENT consumer cluster, point that bundle's prerequisites"
echo "  (garden-kubeconfig + config.env) at your consumer first. Stage 1 + the controller image"
echo "  are already generic. See Federation/FEDERATION-GUIDE.md §6."
echo ""

: "${PROVIDER_KUBECONFIG:=}"; : "${CONSUMER_KUBECONFIG:=}"
if [ -z "$PROVIDER_KUBECONFIG" ]; then printf "  PROVIDER kubeconfig path: "; read -r PROVIDER_KUBECONFIG; fi
if [ -z "$CONSUMER_KUBECONFIG" ]; then printf "  CONSUMER kubeconfig path: "; read -r CONSUMER_KUBECONFIG; fi
[ -s "$PROVIDER_KUBECONFIG" ] || { echo "  ERROR: PROVIDER kubeconfig not found: $PROVIDER_KUBECONFIG"; exit 1; }
[ -s "$CONSUMER_KUBECONFIG" ] || { echo "  ERROR: CONSUMER kubeconfig not found: $CONSUMER_KUBECONFIG"; exit 1; }
export PROVIDER_KUBECONFIG CONSUMER_KUBECONFIG

# 0. reachability gate (advisory)
say "Stage 0 — checking consumer→provider shoot API reachability (auth-gated is expected)…"
PA=$(kubectl --kubeconfig "$PROVIDER_KUBECONFIG" config view -o jsonpath='{.clusters[0].cluster.server}' 2>/dev/null)
echo "  provider API: $PA  (a consumer pod hitting this should get 401 = reachable, auth-gated)"

# 1. provider credential → stored on consumer
say "Stage 1 — provider ServiceAccount credential…"
bash "$FED/stage1-credential.sh"

# 2. federated tile on the consumer kcp
say "Stage 2 — federated tile + provider workspace on the consumer kcp…"
bash "$FED/stage2-provider.sh"

# 3. federation controller + syncagent on the consumer (Stages 4+6 fold in per-Subscription)
say "Stage 3 — federation controller + syncagent on the consumer…"
bash "$FED/stage3-deploy.sh"

echo ""
ok "DONE (federated). The consumer Marketplace now shows 'AI Trust Platform (on <provider>)'."
echo "   Enabling it provisions a fed-<org> tenant on the provider + brokers SSO. See Federation/FEDERATION-GUIDE.md."
echo "   Verify: bash Federation/stage5-verify.sh    Test an org: bash Federation/stage6-reciprocal-test.sh"
