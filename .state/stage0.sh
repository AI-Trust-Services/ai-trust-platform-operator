#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
echo "=== login/mint check ==="
rm -f "$SHOOT_KUBECONFIG"
mint_shoot_kubeconfig >/dev/null 2>&1 && echo "  LOGIN_OK" || { echo "  LOGIN_EXPIRED — run prerequisites/login.sh"; exit 3; }
echo "=== cert-p1 Certificate CR state ==="
sk -n platform-mesh-system get certificate cert-p1 -o jsonpath='state={.status.state} dnsNames={.spec.dnsNames} secretRef={.spec.secretRef.name}/{.spec.secretRef.namespace} expiry={.status.expirationDate}{"\n"}' 2>&1 | grep -av memcache
echo "=== the cert-p1 SECRET — is it REAL LE material (issuer NOT the local CA)? ==="
SECNS=$(sk -n platform-mesh-system get certificate cert-p1 -o jsonpath='{.spec.secretRef.namespace}' 2>/dev/null); SECNS=${SECNS:-platform-mesh-system}
SEC=$(sk -n platform-mesh-system get certificate cert-p1 -o jsonpath='{.spec.secretRef.name}' 2>/dev/null); SEC=${SEC:-cert-p1}
echo "secret = $SECNS/$SEC"
sk -n "$SECNS" get secret "$SEC" -o jsonpath='{.data.tls\.crt}' 2>/dev/null | base64 -d 2>/dev/null | openssl x509 -noout -issuer -subject -dates 2>&1 | grep -av memcache
echo "=== SANs ==="
sk -n "$SECNS" get secret "$SEC" -o jsonpath='{.data.tls\.crt}' 2>/dev/null | base64 -d 2>/dev/null | openssl x509 -noout -ext subjectAltName 2>&1 | grep -av memcache | tail -3
echo "=== current gateway listeners + their certificateRefs (baseline) ==="
sk -n platform-mesh-system get gateway k8sapi-gateway -o jsonpath='{range .spec.listeners[*]}{.name}{" host="}{.hostname}{" certRef="}{.tls.certificateRefs[0].name}{"\n"}{end}' 2>&1 | grep -av memcache
