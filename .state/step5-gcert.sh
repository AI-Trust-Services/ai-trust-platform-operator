#!/bin/bash
exec > /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP/.state/step5-gcert.out 2>&1
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
[ -s "$SHOOT_KUBECONFIG" ] || mint_shoot_kubeconfig || { echo LOGIN_EXPIRED; exit 3; }
GWNS=platform-mesh-system

echo "############ gardener Certificate 'domain-certificate' — what does IT issue? (the durability threat to served cert) ############"
kubectl -n "$GWNS" get certificate.cert.gardener.cloud domain-certificate -o yaml 2>&1 | grep -avi memcache \
  | grep -iE 'name:|secretRef|commonName|dnsNames|- \*|issuerRef|state:|expirationTimestamp|message:' | head -30

echo
echo "############ Is it Flux/Helm-owned (infra)? — determines how to change it durably ############"
kubectl -n "$GWNS" get certificate.cert.gardener.cloud domain-certificate -o jsonpath='labels={.metadata.labels}{"\n"}annos={.metadata.annotations}{"\n"}owner={.metadata.ownerReferences}{"\n"}' 2>&1 | grep -avi memcache | tr ',' '\n' | grep -iE 'helm|flux|managed-by|release|owner|kind' | head

echo
echo "############ Compare: does its issued cert currently match what we SERVE (LE) or would it REVERT us? ############"
echo "-- what the gardener cert's OWN secret currently holds (it writes domain-certificate) --"
echo "   NOTE: we overwrote domain-certificate with LE bytes; if the gardener cert reconciles it will rewrite to ITS issuance."
kubectl -n "$GWNS" get certificate.cert.gardener.cloud domain-certificate -o jsonpath='{.status.state} lastUpdate={.status.lastPendingTimestamp}{"\n"}' 2>&1 | grep -avi memcache
echo "-- the gardener cert dnsNames (does it even cover apex + *.ai-trust-1?) --"
kubectl -n "$GWNS" get certificate.cert.gardener.cloud domain-certificate -o jsonpath='cn={.spec.commonName} dns={.spec.dnsNames}{"\n"}' 2>&1 | grep -avi memcache

echo
echo "############ Also: was our overwrite already reconciled away? (re-check served secret issuer NOW) ############"
kubectl -n "$GWNS" get secret domain-certificate -o jsonpath='{.data.tls\.crt}' 2>/dev/null | base64 -d 2>/dev/null | openssl x509 -noout -issuer -enddate 2>&1 | grep -avi memcache
echo DONE
