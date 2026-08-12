#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
echo "=== create NEW full-SAN managed Certificate (additive; touches nothing served) ==="
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
    - "*.aitrust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu"
  secretRef:
    name: cert-aitrust-full
    namespace: platform-mesh-system
EOF
echo "=== wait for Ready (up to ~5 min for LE DNS-01) ==="
for i in $(seq 1 30); do
  ST=$(kubectl -n platform-mesh-system get certificate.cert.gardener.cloud cert-aitrust-full -o jsonpath='{.status.state}' 2>/dev/null)
  MSG=$(kubectl -n platform-mesh-system get certificate.cert.gardener.cloud cert-aitrust-full -o jsonpath='{.status.message}' 2>/dev/null)
  echo "  state=$ST  $MSG"
  [ "$ST" = "Ready" ] && break
  [ "$ST" = "Error" ] && { echo "  CERT ERROR — will NOT proceed to swap"; break; }
  sleep 10
done
echo "=== verify the issued secret: real LE + covers all SANs ==="
kubectl -n platform-mesh-system get secret cert-aitrust-full -o jsonpath='{.data.tls\.crt}' 2>/dev/null | base64 -d 2>/dev/null | openssl x509 -noout -issuer -subject 2>&1 | grep -av memcache
kubectl -n platform-mesh-system get secret cert-aitrust-full -o jsonpath='{.data.tls\.crt}' 2>/dev/null | base64 -d 2>/dev/null | openssl x509 -noout -ext subjectAltName 2>&1 | grep -av memcache | tail -3
