cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
exec > .state/kcp-wac.out 2>&1

setup_kcp >/dev/null 2>&1; kcp_portforward >/dev/null 2>&1
for i in $(seq 1 15); do kc root get workspace >/dev/null 2>&1 && break; sleep 2; done

echo "===== root WAC orgs-authentication (full yaml) ====="
kc root get workspaceauthenticationconfiguration orgs-authentication -o yaml 2>&1 | grep -avi memcache

echo
echo "===== list WACs in root:orgs ====="
kc root:orgs get workspaceauthenticationconfiguration 2>&1 | grep -avi memcache
