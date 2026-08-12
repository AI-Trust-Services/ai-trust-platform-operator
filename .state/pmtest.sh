#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh
load_config
setup_kcp
kcp_portforward
trap 'pkill -f "port-forward.*root-proxy.*6443" 2>/dev/null || true' EXIT
ws_kubeconfig "$PROVIDER_WS" "$STATE/ws-aitrust.kubeconfig"
echo "=== reach provider ws ==="
kc "$PROVIDER_WS" get apiexport 2>&1 | head
echo "=== helm template locally (sanity) ==="
helm template x "$AITRUST_PM_CHART" --set exportName="$EXPORT_NAME" --set content.publicHost="$AITRUST_CONTENT_HOST" 2>&1 | head -3
echo "=== helm install pm (timeout 100s), FULL output ==="
timeout 100 helm --kubeconfig "$STATE/ws-aitrust.kubeconfig" upgrade -i aitrust-pm "$AITRUST_PM_CHART" \
  --namespace aitrust --create-namespace \
  --set exportName="$EXPORT_NAME" --set content.publicScheme=http --set content.publicHost="$AITRUST_CONTENT_HOST" 2>&1
echo "helmexit=$?"
echo "=== APIExport present now? ==="
kc "$PROVIDER_WS" get apiexport 2>&1 | head
