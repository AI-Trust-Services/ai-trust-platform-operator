#!/bin/bash
# READ-ONLY probe for Task C. No apply/patch/delete/restart/scale.
set +e
cd "$(dirname "$0")/.." || exit 1
source scripts/lib.sh
load_config

echo "===== 1. garden reachability (list shoot, no mint) ====="
timeout 25 garden -n "$PROJECT" get shoot "$SHOOT_NAME" -o jsonpath='{.status.lastOperation.state}{" "}{.metadata.name}{"\n"}' 2>&1 | head -5
rc=$?
echo "garden-list-rc=$rc"
if [ "$rc" -ne 0 ]; then
  echo "GARDEN_LOGIN_LIKELY_EXPIRED"
fi

echo
echo "===== 2. mint shoot kubeconfig (bounded, non-interactive) ====="
timeout 40 bash -c '
  source scripts/lib.sh; load_config
  resp="$(garden create -f - --raw "/apis/core.gardener.cloud/v1beta1/namespaces/${PROJECT}/shoots/${SHOOT_NAME}/adminkubeconfig" <<< "{\"apiVersion\":\"authentication.gardener.cloud/v1alpha1\",\"kind\":\"AdminKubeconfigRequest\",\"spec\":{\"expirationSeconds\":14400}}" 2>&1)"
  if echo "$resp" | grep -q kubeconfig; then
    echo "$resp" | jq -r ".status.kubeconfig" | base64 -d > .state/shoot-kubeconfig.yaml
    echo "MINT_OK"
  else
    echo "MINT_FAIL"
    echo "$resp" | head -3
  fi
'
echo "mint-rc=$?"
