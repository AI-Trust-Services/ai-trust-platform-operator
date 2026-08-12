cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
exec > .state/poc-wac.out 2>&1

setup_kcp >/dev/null 2>&1; kcp_portforward >/dev/null 2>&1
for i in $(seq 1 15); do kc root get workspace >/dev/null 2>&1 && break; sleep 2; done

echo "===== poc WAC (freshest org, 33m) cert count + issuer + subjects ====="
kc root:orgs get workspaceauthenticationconfiguration poc -o jsonpath='{.spec.jwt[0].issuer.url}' 2>&1 | grep -avi memcache
echo
echo "--- cert count in poc WAC certificateAuthority ---"
kc root:orgs get workspaceauthenticationconfiguration poc -o jsonpath='{.spec.jwt[0].issuer.certificateAuthority}' 2>&1 | grep -avi memcache | grep -c "BEGIN CERTIFICATE"
echo
echo "--- subjects of certs in poc WAC ---"
kc root:orgs get workspaceauthenticationconfiguration poc -o jsonpath='{.spec.jwt[0].issuer.certificateAuthority}' 2>&1 | grep -avi memcache | openssl storeutl -certs /dev/stdin 2>/dev/null | grep -iE 'subject|Standard Platform|Root YR|Encrypt'
echo
echo "===== creationTimestamp of poc WAC ====="
kc root:orgs get workspaceauthenticationconfiguration poc -o jsonpath='{.metadata.creationTimestamp}' 2>&1 | grep -avi memcache
echo
echo "===== compare: mirceatest3 (22h, pre-change stamp) cert count ====="
kc root:orgs get workspaceauthenticationconfiguration mirceatest3 -o jsonpath='{.spec.jwt[0].issuer.certificateAuthority}' 2>&1 | grep -avi memcache | grep -c "BEGIN CERTIFICATE"
