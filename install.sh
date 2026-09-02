#!/bin/bash
# ============================================================================
#  install.sh — installer for the AI Trust Platform MSP provider.
#
#  Runs the standard single-cluster deploy: app + Platform Mesh on ONE shoot
#  (the payload cluster). Each Enable creates a Subscription and the operator
#  provisions a per-tenant Keycloak realm inside the shared app.
#
#  Usage:  MSYS_NO_PATHCONV=1 wsl.exe -d Ubuntu -- bash '<bundle>/install.sh' [--mode local|federated]
#
#  --mode local      (default) single-cluster deploy — operator runs in-cluster
#  --mode federated  cross-cluster deploy — operator uses REMOTE_KUBECONFIG to
#                    provision on the payload cluster from a Central controller
# ============================================================================
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
c_blu=$'\033[36m'; c_grn=$'\033[32m'; c_rst=$'\033[0m'
say(){ echo "${c_blu}==>${c_rst} $*"; }
ok(){  echo "${c_grn}OK${c_rst} $*"; }

FEDERATION_MODE=local
while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode) FEDERATION_MODE="$2"; shift 2 ;;
    *) echo "Unknown flag: $1"; exit 1 ;;
  esac
done
if [[ "$FEDERATION_MODE" != "local" && "$FEDERATION_MODE" != "federated" ]]; then
  echo "Error: --mode must be 'local' or 'federated'"; exit 1
fi
export FEDERATION_MODE

echo ""
echo "######################################################################"
echo "#  AI Trust Platform installer"
echo "######################################################################"
echo ""
echo "  Mode: $FEDERATION_MODE"
echo ""
echo "  The AI Trust Platform runs as ONE shared multi-tenant app alongside its"
echo "  own Platform Mesh on a single 'payload' cluster (default: ai-trust-1)."
echo "  Each tenant gets an isolated Keycloak realm + Postgres schema + ClickHouse"
echo "  DB + MinIO bucket provisioned by the operator on Subscription."
echo ""
echo "  Prerequisites: scripts/prerequisites/config.env must be configured."
echo "  Login first:   bash scripts/prerequisites/login.sh"
echo ""

say "Running the provider install (scripts/deploy.sh)…"
bash "$HERE/scripts/deploy.sh"
echo ""
ok "DONE. Platform Mesh now shows the AI Trust Platform tile."
