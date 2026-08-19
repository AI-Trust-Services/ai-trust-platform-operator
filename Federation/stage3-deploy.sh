#!/bin/bash
# Stage 3 deploy — federation controller + sync-agent on PROD (ns aitrust-remote).
# Makes the Stage-2 tile ENABLE-ABLE (syncagent publishes the subscriptions resource) and wires the
# controller to provision federated tenants ON ai-trust-1 via the Stage-1 SA kubeconfig.
set -uo pipefail
FED="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUNDLE="/mnt/c/Claude/projects/eu-ai-trust-prod/Standard_AiTrust_MT_MSP"
source "$BUNDLE/scripts/lib.sh"; load_config
f(){ grep -avi memcache; }

REMOTE_WS="root:providers:ai-trust-remote"
REMOTE_EXPORT="sub.aitrust.remote"
NS="aitrust-remote"
IMG="mirceacraciun795/aitrust-federation:aitrust"
A1_SUFFIX="ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu"
A1_KC_INTERNAL="http://keycloak-service.platform-mesh-system.svc.cluster.local:8080/keycloak"
A1_KC_PUBLIC="https://${A1_SUFFIX}/keycloak"
DBMIGRATE="mirceacraciun795/aitrust-db-migrate:aitrust-67ee2c5"
CHMIGRATE="mirceacraciun795/aitrust-clickhouse-migrate:aitrust-67ee2c5"

echo "=== 0. prod shoot + kcp ==="
cp /mnt/c/claude/projects/eu-ai-trust-prod/.fed_shoot-prod.kubeconfig "$BUNDLE/.state/shoot-kubeconfig.yaml" 2>/dev/null || true
[ -s "$SHOOT_KUBECONFIG" ] || mint_shoot_kubeconfig
setup_kcp; kcp_portforward
trap 'pkill -f "port-forward.*root-proxy.*6443" 2>/dev/null || true' EXIT

echo "=== 1. syncagent image (reuse the one the local provider already runs) ==="
SA_IMG=$(sk -n aitrust-msp get deploy aitrust-syncagent -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null)
[ -z "$SA_IMG" ] && SA_IMG="ghcr.io/kcp-dev/api-syncagent:v0.5.1"
echo "  syncagent image: $SA_IMG"

echo "=== 2. build kcp kubeconfig for $REMOTE_WS (server → in-cluster :8443 + insecure) ==="
KC_WS="$BUNDLE/.state/kcp-remote-incluster.yaml"
cp "$KCP_ADMIN_RAW" "$KC_WS"
python3 - "$KC_WS" "$KCP_INCLUSTER_URL/clusters/$REMOTE_WS" <<'PY'
import sys, re
p, server = sys.argv[1], sys.argv[2]
out=[]
for ln in open(p).read().splitlines():
    if 'certificate-authority-data:' in ln or 'tls-server-name:' in ln: continue
    if re.match(r'\s*server: https://', ln):
        ind=ln[:len(ln)-len(ln.lstrip())]
        out.append(f'{ind}server: {server}'); out.append(f'{ind}insecure-skip-tls-verify: true'); continue
    out.append(ln)
open(p,'w').write('\n'.join(out)+'\n')
PY

echo "=== 3. apply CRD + controller (ns $NS) on prod ==="
sed -e "s|__IMG__|$IMG|g" -e "s|__A1_DOMAIN_SUFFIX__|$A1_SUFFIX|g" \
    -e "s|__A1_KC_INTERNAL__|$A1_KC_INTERNAL|g" -e "s|__A1_KC_PUBLIC__|$A1_KC_PUBLIC|g" \
    -e "s|__DBMIGRATE__|$DBMIGRATE|g" -e "s|__CHMIGRATE__|$CHMIGRATE|g" \
    "$FED/stage3-federation-deploy.yaml" | sk apply -f - 2>&1 | f

echo "=== 4. syncagent kcp kubeconfig Secret + syncagent ==="
sk -n "$NS" create secret generic aitrust-remote-kcp-kubeconfig --from-file=kubeconfig="$KC_WS" \
  --dry-run=client -o yaml 2>/dev/null | sk apply -f - 2>&1 | f
sed -e "s|__SYNCAGENT_IMAGE__|$SA_IMG|g" "$FED/stage3-syncagent.yaml" | sk apply -f - 2>&1 | f

echo "=== 5. syncagent hostAlias fix (root.kcp.localhost → frontproxy ClusterIP) ==="
patch_syncagent_hostalias "$NS" aitrust-remote-syncagent

echo "=== 6. rollouts ==="
KUBECONFIG="$SHOOT_KUBECONFIG" kubectl -n "$NS" rollout status deploy/aitrust-federation --timeout=150s 2>&1 | f
KUBECONFIG="$SHOOT_KUBECONFIG" kubectl -n "$NS" rollout status deploy/aitrust-remote-syncagent --timeout=150s 2>&1 | f

echo "=== 7. wait for APIExport $REMOTE_EXPORT to publish subscriptions ==="
for i in $(seq 1 30); do
  kc "$REMOTE_WS" get apiexport "$REMOTE_EXPORT" -o jsonpath='{range .spec.resources[*]}{.name}{"\n"}{end}' 2>/dev/null | grep -qx subscriptions && { echo "  PUBLISHED"; break; }
  sleep 10
done
echo "  APIExport resources: $(kc "$REMOTE_WS" get apiexport "$REMOTE_EXPORT" -o jsonpath='{range .spec.resources[*]}{.name}{" "}{end}' 2>&1 | f)"
echo "=== 8. pod health ==="
sk -n "$NS" get pods 2>&1 | f
echo DONE_STAGE3_DEPLOY
