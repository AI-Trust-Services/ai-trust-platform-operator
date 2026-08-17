#!/bin/bash
# 6-create-subscription.sh — create one Subscription in the consumer account (the customer's "Create"
# action in the portal). It does NOT stamp an app copy: the syncagent mirrors it to a per-consumer
# namespace on the shoot, where the MT operator provisions a TENANT (a per-tenant Keycloak realm whose
# tokens carry tenant_id) inside the ONE shared app deployed by 3b-shared-app.sh.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; source "$HERE/lib.sh"; load_config
[ -s "$SHOOT_KUBECONFIG" ] || mint_shoot_kubeconfig
setup_kcp; kcp_portforward
trap 'pkill -f "port-forward.*root-proxy.*6443" 2>/dev/null || true' EXIT
WS="root:orgs:$ORG_NAME:$ACCOUNT_NAME"

log "Creating Subscription '$INSTANCE_NAME' (plan=$INSTANCE_PLAN) in $WS…"
kc "$WS" -n default apply -f - <<EOF >/dev/null
apiVersion: sub.aitrust.msp/v1alpha1
kind: Subscription
metadata: { name: ${INSTANCE_NAME} }
spec:
  org: ${ORG_NAME}
  displayName: "AI Trust — ${ACCOUNT_NAME}"
  plan: ${INSTANCE_PLAN}
  adminEmail: ${DEMO_USER}
EOF
ok "Subscription created — the MT operator is now provisioning the tenant realm in the shared app (~1-2 min)"

# Report the mirrored status as the operator fills it in.
log "Watching status (Ctrl-C to stop; step 7 waits for Ready)…"
for _ in $(seq 1 6); do
  kc "$WS" -n default get subscription "$INSTANCE_NAME" \
    -o jsonpath='  phase={.status.phase} ready={.status.ready} url={.status.url} realm={.status.realm}{"\n"}' 2>/dev/null || true
  sleep 10
done
