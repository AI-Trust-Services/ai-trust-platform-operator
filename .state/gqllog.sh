#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
echo "=== graphql gateway logs mentioning aitrust / undefined / schema errors ==="
sk -n "$MESH_NS" logs deploy/kubernetes-graphql-gateway --tail=200 2>&1 | grep -av memcache \
  | grep -iE 'aitrust|trust.ai|undefined|schema|error|failed|v1alpha1' | tail -20
echo "=== gateway-listener logs too ==="
sk -n "$MESH_NS" logs deploy/kubernetes-graphql-gateway-listener --tail=100 2>&1 | grep -av memcache \
  | grep -iE 'aitrust|trust.ai|undefined|error|failed' | tail -10
echo "=== my APIResourceSchema spec.versions[0].schema — does spec have typed properties? ==="
SCH=v3e8f1826.aitrustplatforminstances.trust.ai-trust.msp
setup_kcp >/dev/null 2>&1; kcp_portforward >/dev/null 2>&1; trap 'pkill -f "port-forward.*root-proxy.*6443" 2>/dev/null||true' EXIT
kc "$PROVIDER_WS" get apiresourceschema "$SCH" -o jsonpath='{.spec.versions[0].schema}' 2>&1 | grep -av memcache | head -c 800; echo
