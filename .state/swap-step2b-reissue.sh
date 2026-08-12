#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
echo "=== which SANs actually issue? test each individually is overkill — cert-p1(*.ai-trust-1) + cert-p2(apex) already Ready."
echo "=== the failing SAN was *.aitrust-1 (typo listener). *.services is untested — check if it resolves/issues."
echo "=== delete the failed full cert ==="
kubectl -n platform-mesh-system delete certificate.cert.gardener.cloud cert-aitrust-full --ignore-not-found 2>&1 | grep -av memcache
echo "=== reissue WITHOUT *.aitrust-1 (drop the stale typo host). SANs: apex + *.ai-trust-1 + *.services ==="
cat <<'EOF' | kubectl apply -f - 2>&1 | grep -av memcache
apiVersion: cert.gardener.cloud/v1alpha1
kind: Certificate
metadata:
  name: cert-aitrust-full
  namespace: platform-mesh-system
spec:
  dnsNames:
    - ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu
    - "*.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu"
    - "*.services.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu"
  secretRef:
    name: cert-aitrust-full
    namespace: platform-mesh-system
EOF
for i in $(seq 1 30); do
  ST=$(kubectl -n platform-mesh-system get certificate.cert.gardener.cloud cert-aitrust-full -o jsonpath='{.status.state}' 2>/dev/null)
  MSG=$(kubectl -n platform-mesh-system get certificate.cert.gardener.cloud cert-aitrust-full -o jsonpath='{.status.message}' 2>/dev/null)
  echo "  state=$ST  ${MSG:0:130}"
  [ "$ST" = "Ready" ] && break
  [ "$ST" = "Error" ] && { echo "  ERROR"; break; }
  sleep 10
done
echo "=== verify issued secret ==="
kubectl -n platform-mesh-system get secret cert-aitrust-full -o jsonpath='{.data.tls\.crt}' 2>/dev/null | base64 -d 2>/dev/null | openssl x509 -noout -issuer 2>&1 | grep -av memcache
kubectl -n platform-mesh-system get secret cert-aitrust-full -o jsonpath='{.data.tls\.crt}' 2>/dev/null | base64 -d 2>/dev/null | openssl x509 -noout -ext subjectAltName 2>&1 | grep -av memcache | tail -3
