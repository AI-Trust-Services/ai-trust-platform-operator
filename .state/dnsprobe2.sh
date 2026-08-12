#!/bin/bash
# READ-ONLY probe v2. Non-interactive; hard-fail if garden needs a login.
set +e
cd "$(dirname "$0")/.." || exit 1
source scripts/lib.sh
load_config
export GIT_TERMINAL_PROMPT=0
# force any oidc/kubelogin to NOT open a browser or block on stdin
export KUBECTL_INTERACTIVE=0

TO=/usr/bin/timeout
[ -x "$TO" ] || TO=timeout

echo "===== whoami / kubectl present ====="
which kubectl jq base64 2>&1 | head -5

echo
echo "===== garden get shoot (25s cap, stdin closed) ====="
$TO 25 garden -n "$PROJECT" get shoot "$SHOOT_NAME" \
  -o jsonpath='{.metadata.name}{" state="}{.status.lastOperation.state}{"\n"}' </dev/null 2>&1 | head -8
echo "garden-list-rc=${PIPESTATUS[0]}"

echo
echo "===== raw adminkubeconfig request (30s cap, stdin=the payload only) ====="
PAYLOAD='{"apiVersion":"authentication.gardener.cloud/v1alpha1","kind":"AdminKubeconfigRequest","spec":{"expirationSeconds":14400}}'
resp="$($TO 30 garden create -f - --raw "/apis/core.gardener.cloud/v1beta1/namespaces/${PROJECT}/shoots/${SHOOT_NAME}/adminkubeconfig" <<<"$PAYLOAD" 2>&1)"
rc=$?
echo "mint-rc=$rc"
if [ "$rc" -eq 124 ]; then echo "RESULT=GARDEN_LOGIN_EXPIRED_TIMED_OUT_ON_OIDC"; fi
if echo "$resp" | grep -q '"kubeconfig"'; then
  echo "$resp" | jq -r '.status.kubeconfig' | base64 -d > .state/shoot-kubeconfig.yaml
  echo "RESULT=MINT_OK bytes=$(wc -c < .state/shoot-kubeconfig.yaml)"
else
  echo "RESULT=NO_KUBECONFIG_IN_RESPONSE (first 6 lines):"
  echo "$resp" | grep -aiv -E 'BEGIN|END|[A-Za-z0-9+/]{40,}' | head -6
fi
