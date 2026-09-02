#!/bin/bash
# ============================================================================
#  deploy.sh — publish the AI Trust Platform (multi-tenant) as an MSP provider on the payload cluster
#  (currently ai-trust-1: the cluster that runs the app + all federated tenants).
#  ONE shared app is deployed once (3b); each Enable creates a Subscription and the operator provisions
#  a per-tenant Keycloak realm inside that shared app — it does NOT stamp an app copy.
#  Refresh garden login first (Ubuntu terminal):  bash scripts/prerequisites/login.sh
#  Then:  MSYS_NO_PATHCONV=1 wsl.exe -d Ubuntu -- bash '<bundle>/scripts/deploy.sh'
# ============================================================================
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; source "$HERE/lib.sh"

echo ""
echo "######################################################################"
echo "#  AI Trust Platform — multi-tenant MSP provider on the payload cluster (ai-trust-1)"
echo "######################################################################"

bash "$HERE/0-check-prerequisites.sh" || die "Prerequisites incomplete — fix ❌ above and re-run."
load_config

bash "$HERE/1-worker-pool.sh"
bash "$HERE/2-build-operator-image.sh"
bash "$HERE/2b-build-app-images.sh"
bash "$HERE/3-provider.sh"
bash "$HERE/3b-shared-app.sh"
bash "$HERE/4-consumer-workspace.sh"
bash "$HERE/5-bind-apis.sh"
bash "$HERE/6-create-subscription.sh"
bash "$HERE/7-verify-portal.sh"

echo ""
ok "DONE. AI Trust Platform published as an MSP provider; shared app live + a demo tenant subscribed."
echo "   Reset (remove subscriptions + shared app + provider, keep the mesh): bash scripts/reset.sh   (--pool also drops $WORKER_POOL)"
