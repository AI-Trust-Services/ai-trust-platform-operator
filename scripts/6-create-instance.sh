#!/bin/bash
# 6-create-instance.sh — create one AITrustPlatformInstance in the consumer account (the customer's
# "create my instance" action). The syncagent mirrors it to a per-consumer namespace on the shoot,
# where the operator stamps out the full app copy.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; source "$HERE/lib.sh"; load_config
[ -s "$SHOOT_KUBECONFIG" ] || mint_shoot_kubeconfig
setup_kcp; kcp_portforward
trap 'pkill -f "port-forward.*root-proxy.*6443" 2>/dev/null || true' EXIT
WS="root:orgs:$ORG_NAME:$ACCOUNT_NAME"

log "Creating AITrustPlatformInstance '$INSTANCE_NAME' (size=$INSTANCE_SIZE) in $WS…"
kc "$WS" -n default apply -f - <<EOF >/dev/null
apiVersion: trust.aitrust.msp/v1alpha1
kind: AITrustPlatformInstance
metadata: { name: ${INSTANCE_NAME} }
spec:
  displayName: "AI Trust — ${ACCOUNT_NAME}"
  sizeClass: ${INSTANCE_SIZE}
  adminEmail: ${DEMO_USER}
EOF
ok "instance CR created — the operator is now stamping the full app copy (takes ~5-8 min)"

# Report the mirrored status as the operator fills it in.
log "Watching status (Ctrl-C to stop; step 7 waits for Ready)…"
for _ in $(seq 1 6); do
  kc "$WS" -n default get aitrustplatforminstance "$INSTANCE_NAME" \
    -o jsonpath='  phase={.status.phase} ready={.status.ready} url={.status.url}{"\n"}' 2>/dev/null || true
  sleep 10
done
