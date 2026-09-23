#!/bin/bash
# 0-check-prerequisites.sh — verify tooling, garden reachability, mesh Ready, DNS, app-repo, charts lint, docker login.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; source "$HERE/lib.sh"; load_config
rc=0
need(){ command -v "$1" >/dev/null 2>&1 && ok "$1 present" || { err "$1 missing"; rc=1; }; }
need kubectl; need helm; need jq; need docker; need python3; need git

log "Garden reachable?"
garden version >/dev/null 2>&1 && ok "garden API reachable" || { err "garden not reachable — run scripts/prerequisites/login.sh"; rc=1; }

log "Mesh Ready on $SHOOT_NAME?"
[ -s "$SHOOT_KUBECONFIG" ] || mint_shoot_kubeconfig
sk -n "$MESH_NS" get deploy portal >/dev/null 2>&1 && ok "platform-mesh portal present" || { err "mesh not found — is Standard_Platform_Mesh installed?"; rc=1; }

log "KCP_INCLUSTER_URL on :8443?"
echo "$KCP_INCLUSTER_URL" | grep -q ':8443' && ok "KCP_INCLUSTER_URL = $KCP_INCLUSTER_URL" || { err "KCP_INCLUSTER_URL must be :8443"; rc=1; }

log "DNS: does $INSTANCE_DOMAIN_SUFFIX resolve?"
if [ -n "${INSTANCE_DOMAIN_SUFFIX:-}" ]; then
  if dig +short "$INSTANCE_DOMAIN_SUFFIX" 2>/dev/null | grep -q '.'; then
    ok "DNS resolves: $INSTANCE_DOMAIN_SUFFIX"
  elif nslookup "$INSTANCE_DOMAIN_SUFFIX" >/dev/null 2>&1; then
    ok "DNS resolves: $INSTANCE_DOMAIN_SUFFIX"
  else
    warn "DNS: $INSTANCE_DOMAIN_SUFFIX does not resolve — wildcard DNS + gateway listener must be configured before step 3b"
    # TODO: also verify the Gateway listener and TLS certificate exist on the shoot
    #       (requires sk get gateway / httproute — deferred, needs shoot access at prereq time)
  fi
else
  warn "INSTANCE_DOMAIN_SUFFIX is empty — set it in config.env before deploying"
fi

log "App repo reachable? ($APP_GIT_URL @ ${APP_GIT_REF_DEFAULT:-main})"
if git ls-remote --exit-code "$APP_GIT_URL" "${APP_GIT_REF_DEFAULT:-main}" >/dev/null 2>&1; then
  ok "app repo reachable: $APP_GIT_URL @ ${APP_GIT_REF_DEFAULT:-main}"
else
  err "app repo not reachable: $APP_GIT_URL @ ${APP_GIT_REF_DEFAULT:-main} — check network access and APP_GIT_REF_DEFAULT in config.env"; rc=1
fi

log "Charts lint?"
helm template x "$HERE/../$AITRUST_APP_CHART" --set kcpKubeconfig.adminContent=FAKE >/dev/null 2>&1 && ok "workload chart templates" || { err "workload chart failed to template"; rc=1; }
helm template x "$HERE/../$AITRUST_PM_CHART" >/dev/null 2>&1 && ok "pm chart templates" || { err "pm chart failed to template"; rc=1; }

log "Docker login (needed to push the operator + MT app images in steps 2/2b)?"
docker info >/dev/null 2>&1 && ok "docker daemon reachable" || warn "docker not reachable — steps 2/2b (build/push) will fail until Docker Desktop is up + logged in"

[ "$rc" -eq 0 ] && ok "prerequisites OK" || die "prerequisites incomplete — fix ❌ above"
