#!/bin/bash
exec > /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP/.state/step1-bundle.out 2>&1
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
[ -s "$SHOOT_KUBECONFIG" ] || mint_shoot_kubeconfig || { echo LOGIN_EXPIRED; exit 3; }
GWNS=platform-mesh-system
BK=.state/backup-dnscert2

echo "############ 1. self-signed mesh CA (domain-certificate-ca) ############"
kubectl -n "$GWNS" get secret domain-certificate-ca -o jsonpath='{.data.tls\.crt}' 2>/dev/null | base64 -d > /tmp/mesh-ca.pem
echo "-- subjects in mesh-ca.pem --"
openssl crl2pkcs7 -nocrl -certfile /tmp/mesh-ca.pem 2>/dev/null | openssl pkcs7 -print_certs -noout 2>/dev/null | grep -avi memcache
echo "-- count --"; grep -c 'BEGIN CERT' /tmp/mesh-ca.pem

echo
echo "############ 2. LE chain from cert-aitrust-full (tls.crt = leaf+intermediates; ca.crt = chain) ############"
kubectl -n "$GWNS" get secret cert-aitrust-full -o jsonpath='{.data.tls\.crt}' 2>/dev/null | base64 -d > /tmp/le-tls.pem
kubectl -n "$GWNS" get secret cert-aitrust-full -o jsonpath='{.data.ca\.crt}'  2>/dev/null | base64 -d > /tmp/le-ca.pem
echo "-- le-tls.pem certs --"; openssl crl2pkcs7 -nocrl -certfile /tmp/le-tls.pem 2>/dev/null | openssl pkcs7 -print_certs -noout 2>/dev/null | grep -avi memcache | grep -E 'subject|issuer'
echo "-- le-ca.pem certs ($(grep -c 'BEGIN CERT' /tmp/le-ca.pem 2>/dev/null)) --"; openssl crl2pkcs7 -nocrl -certfile /tmp/le-ca.pem 2>/dev/null | openssl pkcs7 -print_certs -noout 2>/dev/null | grep -avi memcache | grep -E 'subject|issuer'

echo
echo "############ 3. build combined bundle = mesh CA ++ LE chain (issuer/roots only, dedup leaf) ############"
# We want CA certs that can VERIFY both leaves: the mesh CA, plus LE intermediate(s)+root.
# Prefer le-ca.pem (the issuer chain) if present; else derive issuers from le-tls.pem minus the leaf.
: > /tmp/combined-ca.pem
cat /tmp/mesh-ca.pem >> /tmp/combined-ca.pem
if [ -s /tmp/le-ca.pem ]; then
  cat /tmp/le-ca.pem >> /tmp/combined-ca.pem
else
  # strip the first (leaf) cert from le-tls.pem, keep the rest (intermediates)
  awk 'BEGIN{c=0} /BEGIN CERT/{c++} c>1{print}' /tmp/le-tls.pem >> /tmp/combined-ca.pem
fi
# Always also append the public ISRG Root X1 + LE intermediates via the full tls chain's non-leaf parts as belt-and-suspenders
awk 'BEGIN{c=0} /BEGIN CERT/{c++} c>1{print}' /tmp/le-tls.pem >> /tmp/combined-ca.pem
echo "-- combined-ca.pem total certs: $(grep -c 'BEGIN CERT' /tmp/combined-ca.pem) --"
openssl crl2pkcs7 -nocrl -certfile /tmp/combined-ca.pem 2>/dev/null | openssl pkcs7 -print_certs -noout 2>/dev/null | grep -avi memcache | grep -E 'subject=' | sort -u

echo
echo "############ 4. PROVE the combined bundle verifies BOTH leaves ############"
kubectl -n "$GWNS" get secret domain-certificate  -o jsonpath='{.data.tls\.crt}' 2>/dev/null | base64 -d > /tmp/ss-leaf.pem
echo -n "self-signed leaf vs combined bundle: "; openssl verify -CAfile /tmp/combined-ca.pem -untrusted /tmp/ss-leaf.pem /tmp/ss-leaf.pem 2>&1 | grep -avi memcache | tail -1
echo -n "LE leaf vs combined bundle: ";          openssl verify -CAfile /tmp/combined-ca.pem -untrusted /tmp/le-tls.pem /tmp/le-tls.pem 2>&1 | grep -avi memcache | tail -1

# save the combined bundle + base64 for later steps
cp /tmp/combined-ca.pem "$BK/combined-ca.pem"
base64 -w0 /tmp/combined-ca.pem > "$BK/combined-ca.b64"
echo "SAVED $BK/combined-ca.pem ($(wc -c < "$BK/combined-ca.pem") bytes)"
echo STEP1_DONE
