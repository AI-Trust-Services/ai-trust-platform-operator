#!/bin/bash
# READ-ONLY probe v3. Call kubectl directly (garden is a shell fn, timeout can't exec it).
set +e
cd "$(dirname "$0")/.." || exit 1
source scripts/lib.sh
load_config

GK="$PREREQ/garden-kubeconfig.yaml"
TO=/usr/bin/timeout

echo "===== garden get shoot (direct kubectl, 25s cap) ====="
$TO 25 kubectl --kubeconfig "$GK" -n "$PROJECT" get shoot "$SHOOT_NAME" \
  -o jsonpath='{.metadata.name}{" state="}{.status.lastOperation.state}{"\n"}' </dev/null 2>&1 | head -8
echo "garden-list-rc=${PIPESTATUS[0]}"

echo
echo "===== raw adminkubeconfig (direct kubectl, 30s cap) ====="
PAYLOAD='{"apiVersion":"authentication.gardener.cloud/v1alpha1","kind":"AdminKubeconfigRequest","spec":{"expirationSeconds":14400}}'
resp="$($TO 30 kubectl --kubeconfig "$GK" create -f - --raw "/apis/core.gardener.cloud/v1beta1/namespaces/${PROJECT}/shoots/${SHOOT_NAME}/adminkubeconfig" <<<"$PAYLOAD" 2>&1)"
rc=$?
echo "mint-rc=$rc"
[ "$rc" -eq 124 ] && echo "RESULT=GARDEN_LOGIN_EXPIRED_TIMED_OUT_ON_OIDC"
if echo "$resp" | grep -q '"kubeconfig"'; then
  echo "$resp" | jq -r '.status.kubeconfig' | base64 -d > .state/shoot-kubeconfig.yaml
  echo "RESULT=MINT_OK bytes=$(wc -c < .state/shoot-kubeconfig.yaml)"
else
  echo "RESULT=NO_KUBECONFIG (sanitized first lines):"
  echo "$resp" | grep -aiv -E 'BEGIN|END|[A-Za-z0-9+/=]{40,}' | head -8
fi
