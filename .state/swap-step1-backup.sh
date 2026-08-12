#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
rm -f "$SHOOT_KUBECONFIG"; mint_shoot_kubeconfig >/dev/null 2>&1 && echo "LOGIN_OK" || { echo "LOGIN_EXPIRED — run prerequisites/login.sh"; exit 3; }
export KUBECONFIG="$SHOOT_KUBECONFIG"
BK=.state/backup-cert-swap; mkdir -p "$BK"
echo "=== fresh backup for THIS change ==="
kubectl -n platform-mesh-system get gateway k8sapi-gateway -o yaml > "$BK/gateway.yaml" 2>/dev/null; echo "gateway.yaml $(wc -c < "$BK/gateway.yaml")"
kubectl -n platform-mesh-system get secret domain-certificate cert-p1 -o yaml > "$BK/secrets.yaml" 2>/dev/null; echo "secrets.yaml $(wc -c < "$BK/secrets.yaml")"
kubectl -n platform-mesh-system get helmrelease infra -o yaml > "$BK/hr-infra.yaml" 2>/dev/null; echo "hr-infra.yaml $(wc -c < "$BK/hr-infra.yaml")"
echo "=== baseline: current served cert per key host (must stay working) ==="
LB=130.214.18.166
for H in ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu \
         aitrustg2.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu \
         25veqwflh7syq7fm-d.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu; do
  ISS=$(kubectl -n platform-mesh-system run bl-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet -- sh -c "echo Q | openssl s_client -connect $LB:443 -servername $H 2>/dev/null | openssl x509 -noout -issuer" 2>/dev/null | grep -a issuer)
  echo "  $H -> $ISS"
done
echo "=== current gateway listeners + certRefs (baseline) ==="
kubectl -n platform-mesh-system get gateway k8sapi-gateway -o jsonpath='{range .spec.listeners[*]}{.name}={.tls.certificateRefs[0].name} host={.hostname}{"\n"}{end}' 2>/dev/null | grep -av memcache
echo "=== what issuer/DNSProvider issued cert-p1? (need the same to reissue full-SAN) ==="
kubectl -n platform-mesh-system get certificate.cert.gardener.cloud 2>/dev/null | grep -av memcache | head
kubectl -n platform-mesh-system get certificate.cert.gardener.cloud cert-p1 -o jsonpath='issuerRef={.spec.issuerRef} dnsNames={.spec.dnsNames} secretName={.spec.secretName}{"\n"}' 2>/dev/null | grep -av memcache
