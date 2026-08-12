#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
setup_kcp; kcp_portforward
trap 'pkill -f "port-forward.*root-proxy.*6443" 2>/dev/null || true' EXIT
WS="root:orgs:$ORG_NAME:$ACCOUNT_NAME"
OLDNS=aitp-q3c0weh7suf5hgjk-my-aitrust

echo "=== upgrade workload chart to operator v4 (correct domain + reuse terminate-wildstar) ==="
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
patch_syncagent_hostalias "$PROVIDER_NS" aitrust-syncagent >/dev/null 2>&1

echo "=== delete old instance (wrong-domain) + its namespace, then recreate ==="
kc "$WS" -n default delete aitrustplatforminstance my-aitrust --wait=false 2>&1 | grep -av memcache
sk delete ns "$OLDNS" --wait=false 2>&1 | grep -av memcache
sk -n platform-mesh-system delete httproute "${OLDNS}-app" "${OLDNS}-keycloak" --ignore-not-found 2>&1 | grep -av memcache
sleep 8
kc "$WS" -n default apply -f - <<EOF 2>&1 | grep -av memcache
apiVersion: trust.ai-trust.msp/v1alpha1
kind: AITrustPlatformInstance
metadata: { name: my-aitrust }
spec: { displayName: "AI Trust — tenant", sizeClass: standard, adminEmail: ${DEMO_USER} }
EOF
echo "recreated; operator will stamp with the correct ai-trust-1 host"
