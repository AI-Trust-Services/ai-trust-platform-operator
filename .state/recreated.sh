#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
setup_kcp; kcp_portforward
for i in $(seq 1 15); do kc root get workspace >/dev/null 2>&1 && break; sleep 2; done
trap 'pkill -f "port-forward.*root-proxy.*6443" 2>/dev/null || true' EXIT
WS=root:orgs:aitrustg2:demo

echo "=== upgrade workload chart to operator v6 (fixed manifests) ==="
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
sk -n "$PROVIDER_NS" rollout status deploy/aitrust-msp-operator --timeout=90s 2>&1 | grep -av memcache | tail -1

echo "=== delete instance d (finalizer cleans ns aitp-33hins0iklcwfg45-d + routes) ==="
kc "$WS" -n default delete aitrustplatforminstance d --wait=false 2>&1 | grep -av memcache
sk delete ns aitp-33hins0iklcwfg45-d --wait=false 2>&1 | grep -av memcache
echo "waiting for CR gone…"
for i in $(seq 1 20); do kc "$WS" -n default get aitrustplatforminstance d >/dev/null 2>&1 || { echo gone; break; }; sleep 5; done

echo "=== recreate d (clean, on v6 manifests) ==="
kc "$WS" -n default apply -f - <<EOF 2>&1 | grep -av memcache
apiVersion: trust.aitrust.msp/v1alpha1
kind: AITrustPlatformInstance
metadata: { name: d }
spec: { displayName: "d", sizeClass: standard, adminEmail: mircea.craciun@sap.com }
EOF
ok "d recreated on operator v6 — auth/probe fixes baked in; ~5-8 min to Ready"
