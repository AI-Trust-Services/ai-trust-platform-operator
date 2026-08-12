#!/bin/bash
# Full re-provision after the group rename trust.ai-trust.msp -> trust.aitrust.msp
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
setup_kcp; kcp_portforward
trap 'pkill -f "port-forward.*root-proxy.*6443" 2>/dev/null || true' EXIT

echo "=== 1. apply the NEW-group CRD on the shoot ==="
sk apply -f charts/aitrust-msp-app/crds/aitrustplatforminstance.yaml 2>&1 | grep -av memcache | tail -1

echo "=== 2. clean old pm chart + old APIExport/schema (old group) from the provider ws ==="
ws_kubeconfig "$PROVIDER_WS" "$STATE/ws-aitrust.kubeconfig"
helm --kubeconfig "$STATE/ws-aitrust.kubeconfig" -n aitrust uninstall aitrust-pm 2>&1 | grep -av memcache | tail -1
kc "$PROVIDER_WS" delete apiexport trust.ai-trust.msp --ignore-not-found 2>&1 | grep -av memcache
for s in $(kc "$PROVIDER_WS" get apiresourceschema -o name 2>/dev/null | grep aitrust); do kc "$PROVIDER_WS" delete "$s" 2>&1 | grep -av memcache; done

echo "=== 3. install NEW pm chart (export trust.aitrust.msp) ==="
helm --kubeconfig "$STATE/ws-aitrust.kubeconfig" upgrade -i aitrust-pm "$AITRUST_PM_CHART" \
  --namespace aitrust --create-namespace \
  --set exportName="$EXPORT_NAME" --set content.publicScheme="$CONTENT_SCHEME" --set content.publicHost="$AITRUST_CONTENT_HOST" \
  2>&1 | grep -E 'STATUS|REVISION' | head
xok(){ kc "$PROVIDER_WS" get apiexport "$EXPORT_NAME" >/dev/null 2>&1; }
wait_for 120 5 "APIExport $EXPORT_NAME present" xok

echo "=== 4. upgrade workload chart (operator v5 + new group + syncagent) ==="
cp "$KCP_ADMIN_RAW" "$STATE/kcp-provider-incluster.yaml"
python3 - "$STATE/kcp-provider-incluster.yaml" "$KCP_INCLUSTER_URL/clusters/$PROVIDER_WS" <<'PY'
import sys, re
p, server = sys.argv[1], sys.argv[2]
out=[]
for ln in open(p).read().splitlines():
    if 'certificate-authority-data:' in ln or 'tls-server-name:' in ln: continue
    if re.match(r'\s*server: https://', ln):
        ind=ln[:len(ln)-len(ln.lstrip())]; out.append(f'{ind}server: {server}'); out.append(f'{ind}insecure-skip-tls-verify: true'); continue
    out.append(ln)
open(p,'w').write('\n'.join(out)+'\n')
PY
helm --kubeconfig "$SHOOT_KUBECONFIG" upgrade -i aitrust-msp-app "$AITRUST_APP_CHART" \
  --namespace "$PROVIDER_NS" --create-namespace \
  --set operator.image.repository="$OPERATOR_IMAGE" --set operator.image.tag="$OPERATOR_TAG" \
  --set operator.instanceDomainSuffix="$INSTANCE_DOMAIN_SUFFIX" \
  --set operator.registry="$REGISTRY" --set operator.tag="$TAG" --set operator.mspWorkerLabel="$MSP_WORKER_LABEL" \
  --set exportName="$EXPORT_NAME" \
  --set kcpKubeconfig.inClusterServerUrl="$KCP_INCLUSTER_URL" \
  --set-file kcpKubeconfig.adminContent="$STATE/kcp-provider-incluster.yaml" \
  2>&1 | grep -E 'STATUS|REVISION' | head
patch_syncagent_hostalias "$PROVIDER_NS" aitrust-syncagent >/dev/null 2>&1
bind_authenticated "$PROVIDER_WS"

echo "=== 5. wait for APIExport to publish aitrustplatforminstances (new group) ==="
haveres(){ kc "$PROVIDER_WS" get apiexport "$EXPORT_NAME" -o jsonpath='{range .spec.resources[*]}{.name}{"\n"}{end}' 2>/dev/null | grep -q '^aitrustplatforminstances$'; }
wait_for 300 10 "APIExport publishes aitrustplatforminstances" haveres
kc "$PROVIDER_WS" get apiresourceschema 2>&1 | grep -av memcache | grep aitrust
ok "provider re-published under trust.aitrust.msp"
