#!/bin/bash
# 0-check-prerequisites.sh — verify tooling, garden reachability, mesh Ready, charts lint, docker login.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; source "$HERE/lib.sh"; load_config
rc=0
need(){ command -v "$1" >/dev/null 2>&1 && ok "$1 present" || { err "$1 missing"; rc=1; }; }
need kubectl; need helm; need jq; need docker; need python3

log "Garden reachable?"
garden version >/dev/null 2>&1 && ok "garden API reachable" || { err "garden not reachable — run prerequisites/login.sh"; rc=1; }

log "Mesh Ready on $SHOOT_NAME?"
[ -s "$SHOOT_KUBECONFIG" ] || mint_shoot_kubeconfig
sk -n "$MESH_NS" get deploy portal >/dev/null 2>&1 && ok "platform-mesh portal present" || { err "mesh not found — is Standard_Platform_Mesh installed?"; rc=1; }

log "KCP_INCLUSTER_URL on :8443?"
echo "$KCP_INCLUSTER_URL" | grep -q ':8443' && ok "KCP_INCLUSTER_URL = $KCP_INCLUSTER_URL" || { err "KCP_INCLUSTER_URL must be :8443"; rc=1; }

log "Charts lint?"
helm template x "$HERE/../$AITRUST_APP_CHART" --set kcpKubeconfig.adminContent=FAKE >/dev/null 2>&1 && ok "workload chart templates" || { err "workload chart failed to template"; rc=1; }
helm template x "$HERE/../$AITRUST_PM_CHART" >/dev/null 2>&1 && ok "pm chart templates" || { err "pm chart failed to template"; rc=1; }

log "Docker login (needed to push the operator + MT app images in steps 2/2b)?"
docker info >/dev/null 2>&1 && ok "docker daemon reachable" || warn "docker not reachable — steps 2/2b (build/push) will fail until Docker Desktop is up + logged in"

[ "$rc" -eq 0 ] && ok "prerequisites OK" || die "prerequisites incomplete — fix ❌ above"
