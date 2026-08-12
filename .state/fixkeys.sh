#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
setup_kcp; kcp_portforward
trap 'pkill -f "port-forward.*root-proxy.*6443" 2>/dev/null || true' EXIT
echo "=== upgrade workload chart (new pm-content with apiGroup/entity/entityCollection keys) ==="
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
echo "=== restart content nginx so it serves the new pm-content.json ==="
sk -n "$PROVIDER_NS" rollout restart deployment/aitrust-portal-integration 2>&1 | grep -av memcache
sk -n "$PROVIDER_NS" rollout status deployment/aitrust-portal-integration --timeout=120s 2>&1 | grep -av memcache | tail -1
sleep 5
echo "=== verify served content has apiGroup + entity ==="
for i in 1 2 3; do
  sk -n platform-mesh-system run cv-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet -- \
    curl -sS http://aitrust-portal.aitrust-msp.svc.cluster.local/pm-content.json 2>/dev/null > "$STATE/served2.json"
  [ -s "$STATE/served2.json" ] && break; sleep 3
done
python3 -c "
import json
rd=json.load(open('$STATE/served2.json'))['luigiConfigFragment']['data']['nodes'][0]['context']['resourceDefinition']
print('apiGroup=',rd.get('apiGroup'),'entity=',rd.get('entity'),'entityCollection=',rd.get('entityCollection'),'version=',rd.get('version'))
"
