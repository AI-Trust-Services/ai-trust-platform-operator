#!/bin/bash
# ============================================================================
#  deploy.sh — publish the AI Trust Platform as an MSP provider on ai-trust-1.
#  Refresh garden login first (Ubuntu terminal):  bash prerequisites/login.sh
#  Then:  MSYS_NO_PATHCONV=1 wsl.exe -d Ubuntu -- bash '<bundle>/scripts/deploy.sh'
# ============================================================================
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; source "$HERE/lib.sh"

echo ""
echo "######################################################################"
echo "#  AI Trust Platform — MSP provider on ai-trust-1"
echo "######################################################################"

bash "$HERE/0-check-prerequisites.sh" || die "Prerequisites incomplete — fix ❌ above and re-run."
load_config

bash "$HERE/1-worker-pool.sh"
bash "$HERE/2-build-operator-image.sh"
bash "$HERE/3-provider.sh"
bash "$HERE/4-consumer-workspace.sh"
bash "$HERE/5-bind-apis.sh"
bash "$HERE/6-create-instance.sh"
bash "$HERE/7-verify-portal.sh"

echo ""
ok "DONE. AI Trust published as an MSP provider; a demo instance provisioned for the consumer."
echo "   Reset (remove instances + provider, keep the mesh): bash scripts/reset.sh   (--pool also drops $WORKER_POOL)"
