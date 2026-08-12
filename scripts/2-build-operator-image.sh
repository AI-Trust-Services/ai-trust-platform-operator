#!/bin/bash
# 2-build-operator-image.sh — build + push the MSP operator image (embeds the app manifest set).
# The APP images (postgres/backends/frontends/…) are NOT rebuilt — they already live on $REGISTRY:$TAG
# (built by Standard_Ai_Platform). This step only builds the small operator.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; source "$HERE/lib.sh"; load_config
OP="$HERE/../operator"

# Keep the operator's embedded manifests in sync with the bundle's config/k8s-app (source of truth).
log "Syncing operator/manifests ← config/k8s-app…"
cp "$HERE/../config/k8s-app/"*.yaml "$OP/manifests/" 2>/dev/null || true
cp "$HERE/../config/k8s-app/02-secret-config.tmpl" "$OP/manifests/" 2>/dev/null || true

log "Building $OPERATOR_IMAGE:$OPERATOR_TAG…"
docker build -t "$OPERATOR_IMAGE:$OPERATOR_TAG" "$OP"
log "Pushing…"
docker push "$OPERATOR_IMAGE:$OPERATOR_TAG"
ok "operator image pushed: $OPERATOR_IMAGE:$OPERATOR_TAG"
