#!/bin/bash
# login.sh — run once before deploying to authenticate against the Gardener API.
# Sets KUBECONFIG to the garden kubeconfig and verifies the shoot is reachable.
# Re-run if deploy scripts report "adminkubeconfig failed / access expired".

[ -n "$KUBECONFIG" ] || { echo "ERROR: KUBECONFIG env var is not set — point it at your garden kubeconfig."; exit 1; }
[ -f "$KUBECONFIG" ] || { echo "ERROR: KUBECONFIG file not found: $KUBECONFIG"; exit 1; }

: "${SHOOT_NAME:?SHOOT_NAME is not set}"
: "${PROJECT:?PROJECT is not set}"

echo ">>> Logging into garden (a browser opens or a http://localhost:8000/ URL is printed — log in with your credentials)."
echo ""
kubectl get shoot "$SHOOT_NAME" -n "$PROJECT" -o name
echo ""
echo ">>> If the shoot name shows above, the login is cached. You can now run the deploy scripts."
