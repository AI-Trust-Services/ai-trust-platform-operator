#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
BK=.state/backup-cert-swap
echo "=== full cert-p1 Certificate CR (the working LE wildcard — clone its issuer/dns setup) ==="
kubectl -n platform-mesh-system get certificate.cert.gardener.cloud cert-p1 -o yaml > "$BK/cert-p1-cr.yaml" 2>/dev/null
grep -avE 'managedFields|resourceVersion|uid:|creationTimestamp|generation:|status:' "$BK/cert-p1-cr.yaml" | sed -n '1,60p'
echo "=== how does cert-p1 request DNS names — spec.dnsNames / commonName / issuerRef? ==="
kubectl -n platform-mesh-system get certificate.cert.gardener.cloud cert-p1 -o jsonpath='commonName={.spec.commonName}{"\n"}dnsNames={.spec.dnsNames}{"\n"}issuerRef={.spec.issuerRef}{"\n"}secretRef={.spec.secretRef}{"\n"}secretName={.spec.secretName}{"\n"}' 2>&1 | grep -av memcache
echo "=== is there a default issuer we can rely on (so a new Certificate without issuerRef still works)? ==="
kubectl get issuer.cert.gardener.cloud -A 2>&1 | grep -av memcache | head
echo "=== cert-p2 (apex) spec — proves apex issuance already works via the same path ==="
kubectl -n platform-mesh-system get certificate.cert.gardener.cloud cert-p2 -o jsonpath='p2 dnsNames={.spec.dnsNames} state={.status.state}{"\n"}' 2>&1 | grep -av memcache
