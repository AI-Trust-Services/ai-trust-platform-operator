#!/bin/bash
# 1-worker-pool.sh — add the dedicated worker pool for the ONE SHARED multi-tenant app + the MT operator
# (WORKER_TYPE m_c16_m128_v2, ~128Gi — the shared app + all tenants land here). Labelled
# workload=$MSP_WORKER_LABEL; the shared app (3b) and operator pin their pods here.
# Idempotent; never creates/deletes a shoot.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; source "$HERE/lib.sh"; load_config

if garden get shoot "$SHOOT_NAME" -n "$PROJECT" -o jsonpath='{.spec.provider.workers[*].name}' 2>/dev/null \
     | tr ' ' '\n' | grep -qx "$WORKER_POOL"; then
  ok "worker pool '$WORKER_POOL' already exists — skipping"
else
  IMGVER="${WORKER_IMAGE_VERSION:-}"
  [ -n "$IMGVER" ] || IMGVER="$(garden get shoot "$SHOOT_NAME" -n "$PROJECT" -o jsonpath='{.spec.provider.workers[0].machine.image.version}' 2>/dev/null)"
  [ -n "$IMGVER" ] || die "could not determine worker image version — set WORKER_IMAGE_VERSION"
  log "Adding pool '$WORKER_POOL' ($WORKER_TYPE, zone $WORKER_ZONE, gardenlinux $IMGVER, min$WORKER_MIN/max$WORKER_MAX, label workload=$MSP_WORKER_LABEL)…"
  PATCH="$STATE/worker-pool-patch.json"
  cat > "$PATCH" <<EOF
[{"op":"add","path":"/spec/provider/workers/-","value":{
  "name":"$WORKER_POOL","minimum":$WORKER_MIN,"maximum":$WORKER_MAX,"maxSurge":1,"maxUnavailable":0,
  "machine":{"type":"$WORKER_TYPE","image":{"name":"gardenlinux","version":"$IMGVER"},"architecture":"amd64"},
  "zones":["$WORKER_ZONE"],"cri":{"name":"containerd"},
  "labels":{"workload":"$MSP_WORKER_LABEL"},
  "systemComponents":{"allow":true},"updateStrategy":"AutoRollingUpdate"}}]
EOF
  garden patch shoot "$SHOOT_NAME" -n "$PROJECT" --type=json --patch-file "$PATCH"
  ok "worker pool patch applied — shoot reconciling (~10 min)"
fi

[ -s "$SHOOT_KUBECONFIG" ] || mint_shoot_kubeconfig
# Check the SPECIFIC pool by its Gardener pool label — NOT the shared workload=$MSP_WORKER_LABEL label
# (multiple pools may carry that same node label, which would give a false positive here).
node_ready(){ sk get nodes -l worker.gardener.cloud/pool="$WORKER_POOL" --no-headers 2>/dev/null | grep -q ' Ready '; }
wait_for 1800 20 "a Ready node in pool $WORKER_POOL" node_ready
ok "ai-trust worker node ready"
