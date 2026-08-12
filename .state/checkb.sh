#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
[ -s "$SHOOT_KUBECONFIG" ] || mint_shoot_kubeconfig
setup_kcp; kcp_portforward
trap 'pkill -f "port-forward.*root-proxy.*6443" 2>/dev/null || true' EXIT

WS=root:orgs:aitrustg2:demo
USER=mircea.craciun@sap.com
flt(){ grep -av memcache; }

# Wait until the kcp port-forward actually answers.
for i in $(seq 1 30); do
  if kc root get workspace >/dev/null 2>&1; then break; fi
  sleep 2
  if [ "$i" = "15" ]; then kcp_portforward; fi
done
echo "port-forward ready after ${i}x2s"

echo "=== 0. binding + API served under new group in $WS ==="
kc "$WS" get apibinding 2>&1 | flt | grep -iE 'NAME|aitrust'
kc "$WS" api-resources --api-group=trust.aitrust.msp 2>&1 | flt | head

echo
echo "=== 1. SAR: can $USER create aitrustplatforminstances (group trust.aitrust.msp) in ns default? ==="
kc "$WS" create -o yaml -f - 2>/dev/null <<EOF | flt | grep -iE 'allowed|denied|reason'
apiVersion: authorization.k8s.io/v1
kind: SubjectAccessReview
spec:
  user: ${USER}
  resourceAttributes: { verb: create, group: trust.aitrust.msp, resource: aitrustplatforminstances, version: v1alpha1, namespace: default }
EOF

echo
echo "=== 2. CREATE probe instance 'gqlprobe' AS the user in ns default ==="
kc "$WS" -n default create --as="$USER" -f - 2>&1 <<EOF | flt
apiVersion: trust.aitrust.msp/v1alpha1
kind: AITrustPlatformInstance
metadata: { name: gqlprobe }
spec:
  displayName: probe
  sizeClass: small
  adminEmail: ${USER}
EOF

echo
echo "=== 3. VERIFY it exists ==="
kc "$WS" -n default get aitrustplatforminstance gqlprobe -o wide 2>&1 | flt
echo "--- yaml (spec) ---"
kc "$WS" -n default get aitrustplatforminstance gqlprobe -o jsonpath='name={.metadata.name} group={.apiVersion} displayName={.spec.displayName} sizeClass={.spec.sizeClass} adminEmail={.spec.adminEmail}{"\n"}' 2>&1 | flt

echo
echo "=== 4. DELETE the probe ==="
kc "$WS" -n default delete aitrustplatforminstance gqlprobe 2>&1 | flt

echo
echo "=== 5. confirm gone ==="
kc "$WS" -n default get aitrustplatforminstance gqlprobe 2>&1 | flt | head -3
echo "DONE"
