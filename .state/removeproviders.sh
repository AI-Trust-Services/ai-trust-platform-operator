#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
setup_kcp; kcp_portforward
trap 'pkill -f "port-forward.*root-proxy.*6443" 2>/dev/null || true' EXIT

echo "########## REMOVE private-llm + chat-ui providers ##########"
# 1) delete any instances the tutorial consumer created (finalizers)
for ws in root:orgs:demo:tutorial root:orgs:mirceatest2:test; do
  kc "$ws" -n default delete llminstance --all --wait=false 2>&1 | grep -av memcache
  kc "$ws" -n default delete chatuiinstance --all --wait=false 2>&1 | grep -av memcache
  kc "$ws" -n default delete apitokenrequest --all --wait=false 2>&1 | grep -av memcache
done
# 2) uninstall workload charts on the shoot
helm --kubeconfig "$SHOOT_KUBECONFIG" -n private-llm uninstall private-llm 2>&1 | grep -avE 'memcache' | tail -1
helm --kubeconfig "$SHOOT_KUBECONFIG" -n chat-ui   uninstall chat-ui   2>&1 | grep -avE 'memcache' | tail -1
sk delete ns private-llm chat-ui --wait=false 2>&1 | grep -av memcache
# 3) uninstall pm charts from their provider workspaces
ws_kubeconfig root:providers:private-llm "$STATE/ws-pll.kubeconfig"
helm --kubeconfig "$STATE/ws-pll.kubeconfig" -n private-llm uninstall private-llm-pm 2>&1 | grep -avE 'memcache' | tail -1
ws_kubeconfig root:providers:chat-ui "$STATE/ws-cui.kubeconfig"
helm --kubeconfig "$STATE/ws-cui.kubeconfig" -n chat-ui uninstall chat-ui-pm 2>&1 | grep -avE 'memcache' | tail -1
# 4) delete provider workspaces
kc root:providers delete workspace private-llm --wait=false 2>&1 | grep -av memcache
kc root:providers delete workspace chat-ui --wait=false 2>&1 | grep -av memcache
echo "providers removed."

echo ""
echo "########## INSPECT the gateway GraphQL type for AITrustPlatformInstance ##########"
echo "=== APIResourceSchema versions[0].name + schema.type present? ==="
SCH=v3e8f1826.aitrustplatforminstances.trust.ai-trust.msp
kc "$PROVIDER_WS" get apiresourceschema "$SCH" -o jsonpath='ver={.spec.versions[0].name} storage={.spec.versions[0].storage} served={.spec.versions[0].served} schemaType={.spec.versions[0].schema.type}{"\n"}' 2>&1 | grep -av memcache
echo "=== does the schema have a top-level type:object? (gateway needs it) ==="
kc "$PROVIDER_WS" get apiresourceschema "$SCH" -o jsonpath='{.spec.versions[0].schema.type}{"\n"}' 2>&1 | grep -av memcache
