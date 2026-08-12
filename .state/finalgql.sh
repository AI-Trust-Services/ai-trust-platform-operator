#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
setup_kcp; kcp_portforward
trap 'pkill -f "port-forward.*root-proxy.*6443" 2>/dev/null || true' EXIT
echo "=== provider-ws schema present + APIExport lists resource? ==="
kc "$PROVIDER_WS" get apiresourceschema 2>&1 | grep -av memcache | grep aitrust
kc "$PROVIDER_WS" get apiexport "$EXPORT_NAME" -o jsonpath='resources={range .spec.resources[*]}{.name}{" schema="}{.schema}{" "}{end}{"\n"}' 2>&1 | grep -av memcache
echo "=== gateway-listener: newest lines mentioning the provider cluster / schema (are we past the transient?) ==="
sk -n "$MESH_NS" logs deploy/kubernetes-graphql-gateway-listener --since=3m 2>&1 | grep -av memcache | grep -iE 'schema not found|1xwk2itxtl8w7vm0|ai-trust|Registered|Successfully loaded' | tail -8
echo "=== confirm status schema clean in the CURRENT bound schema ==="
SCH=$(kc "$PROVIDER_WS" get apiresourceschema -o name 2>/dev/null | grep aitrust | head -1)
kc "$PROVIDER_WS" get "$SCH" -o jsonpath='preserveUnknown=[{.spec.versions[0].schema.properties.status.x-kubernetes-preserve-unknown-fields}] statusType={.spec.versions[0].schema.properties.status.type}{"\n"}' 2>&1 | grep -av memcache
