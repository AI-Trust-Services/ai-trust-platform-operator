#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
setup_kcp >/dev/null 2>&1; kcp_portforward >/dev/null 2>&1
trap 'pkill -f "port-forward.*root-proxy.*6443" 2>/dev/null || true' EXIT
echo "=== upgrade workload chart (refresh portal ConfigMap with metadata.name create field) ==="
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
  --set-file kcpKubeconfig.adminContent="$STATE/kcp-provider-incluster.yaml" 2>&1 | grep -E "STATUS|REVISION" | head
echo "=== restart portal nginx so it serves the new pm-content.json ==="
sk -n "$PROVIDER_NS" rollout restart deploy/aitrust-portal-integration 2>&1 | grep -av memcache
sk -n "$PROVIDER_NS" rollout status deploy/aitrust-portal-integration --timeout=90s 2>&1 | grep -av memcache | tail -1
echo "=== verify served content now has metadata.name in createView ==="
sk -n platform-mesh-system run pv-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet -- \
  curl -sS http://aitrust-portal.aitrust-msp.svc.cluster.local/pm-content.json 2>/dev/null \
  | python3 -c "import sys,json;d=json.load(sys.stdin);cv=d['luigiConfigFragment']['data']['nodes'][0]['context']['resourceDefinition']['ui']['createView']['fields'];print('first field:',cv[0])"
echo "=== restart portal so it re-reads (its cache) ==="
sk -n platform-mesh-system rollout restart deploy/portal 2>&1 | grep -av memcache
