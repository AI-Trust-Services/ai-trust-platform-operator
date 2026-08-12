#!/bin/bash
exec > /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP/.state/step5-poc.out 2>&1
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
[ -s "$SHOOT_KUBECONFIG" ] || mint_shoot_kubeconfig || { echo LOGIN_EXPIRED; exit 3; }
setup_kcp >/dev/null 2>&1; kcp_portforward >/dev/null 2>&1
for i in $(seq 1 15); do kc root get workspace >/dev/null 2>&1 && break; sleep 2; done

echo "############ poc WAC: how many certs in its CA? (poc onboarded ~25m ago; was it before/after our bundle patch?) ############"
echo -n "  poc cert count: "; kc root:orgs get workspaceauthenticationconfiguration poc -o jsonpath='{.spec.jwt[0].issuer.certificateAuthority}' 2>/dev/null | grep -avi memcache | grep -c 'BEGIN CERT'
echo "  poc WAC issuers:"; kc root:orgs get workspaceauthenticationconfiguration poc -o jsonpath='{.spec.jwt[0].issuer.certificateAuthority}' 2>/dev/null | grep -avi memcache > /tmp/poc-ca.pem
openssl crl2pkcs7 -nocrl -certfile /tmp/poc-ca.pem 2>/dev/null | openssl pkcs7 -print_certs -noout 2>/dev/null | grep -avi memcache | grep subject= | sort -u
echo "  poc WAC created/updated:"; kc root:orgs get workspaceauthenticationconfiguration poc -o jsonpath='created={.metadata.creationTimestamp} gen={.metadata.generation}{"\n"}' 2>/dev/null | grep -avi memcache

echo
echo "############ CONCLUSION HINT ############"
echo "  If poc has 1 cert (self-signed only) yet was reachable under LE, its token validation would FAIL for a"
echo "  real user login even though the CR is Ready (Ready != user-token-validated)."
echo "  If poc has 5 certs, the account-operator must be reading a source we already fixed OR copied an existing WAC."
echo DONE
