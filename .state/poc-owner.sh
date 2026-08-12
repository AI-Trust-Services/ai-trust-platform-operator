cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
exec > .state/poc-owner.out 2>&1

setup_kcp >/dev/null 2>&1; kcp_portforward >/dev/null 2>&1
for i in $(seq 1 15); do kc root get workspace >/dev/null 2>&1 && break; sleep 2; done

echo "===== poc WAC managedFields managers + annotations (who wrote it) ====="
kc root:orgs get workspaceauthenticationconfiguration poc -o jsonpath='{range .metadata.managedFields[*]}{.manager}{" | "}{.operation}{" | "}{.time}{"\n"}{end}' 2>&1 | grep -avi memcache
echo
echo "--- annotations ---"
kc root:orgs get workspaceauthenticationconfiguration poc -o jsonpath='{.metadata.annotations}' 2>&1 | grep -avi memcache
echo
echo "--- ownerReferences ---"
kc root:orgs get workspaceauthenticationconfiguration poc -o jsonpath='{.metadata.ownerReferences}' 2>&1 | grep -avi memcache
echo
echo "===== does poc WAC have last-applied-configuration (i.e. kubectl apply)? ====="
kc root:orgs get workspaceauthenticationconfiguration poc -o jsonpath='{.metadata.annotations.kubectl\.kubernetes\.io/last-applied-configuration}' 2>&1 | grep -avi memcache | head -c 200
echo
echo "===== is there a WorkspaceType / template carrying the CA? list root workspacetypes ====="
kc root get workspacetype 2>&1 | grep -avi memcache
