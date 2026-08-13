#!/bin/bash
# 2-build-operator-image.sh — build + push the MT subscription operator image ($OPERATOR_IMAGE:$OPERATOR_TAG).
# The MT operator provisions a per-tenant Keycloak realm inside the ONE shared app per Subscription — it does
# NOT stamp app copies, so it embeds ONLY operator/manifests/*.tmpl (the tenant-provision Job template). We do
# NOT sync config/k8s-app into operator/manifests (that was the full-copy MSP operator's behaviour).
# The APP images are built+pushed separately by 2b-build-app-images.sh (tag $TAG).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; source "$HERE/lib.sh"; load_config
OP="$HERE/../operator"

log "Building $OPERATOR_IMAGE:$OPERATOR_TAG (embeds only manifests/*.tmpl)…"
docker build -t "$OPERATOR_IMAGE:$OPERATOR_TAG" "$OP"
log "Pushing…"
docker push "$OPERATOR_IMAGE:$OPERATOR_TAG"
ok "operator image pushed: $OPERATOR_IMAGE:$OPERATOR_TAG"
