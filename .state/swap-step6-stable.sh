#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
echo "=== what issuer is CURRENTLY in the domain-certificate secret (my patch = cert-aitrust-full LE)? ==="
kubectl -n platform-mesh-system get secret domain-certificate -o jsonpath='{.data.tls\.crt}' 2>/dev/null | base64 -d 2>/dev/null | openssl x509 -noout -issuer -subject -ext subjectAltName 2>&1 | grep -av memcache | tail -4
echo "=== the gardener domain-certificate Certificate: does its status point at a DIFFERENT secret internally? ==="
kubectl -n platform-mesh-system get certificate.cert.gardener.cloud domain-certificate -o jsonpath='status.state={.status.state} expiry={.status.expirationDate} lastPending={.status.lastPendingTimestamp} msg={.status.message}{"\n"}' 2>&1 | grep -av memcache
echo "=== KEY QUESTION: will gardener re-sync the secret back to ITS cert (LE apex+*.ai-trust-1)? watch 60s ==="
sleep 60
kubectl -n platform-mesh-system get secret domain-certificate -o jsonpath='{.data.tls\.crt}' 2>/dev/null | base64 -d 2>/dev/null | openssl x509 -noout -issuer -ext subjectAltName 2>&1 | grep -av memcache | tail -3
echo "  (if issuer=Lets Encrypt and SAN includes *.ai-trust-1 => durable + instances covered, regardless of which LE cert)"
