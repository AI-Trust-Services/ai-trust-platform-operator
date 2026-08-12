#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
setup_kcp; kcp_portforward
trap 'pkill -f "port-forward.*root-proxy.*6443" 2>/dev/null || true' EXIT
WS=root:orgs:mirceatest3:accounttest
echo "=== consumer binding picked up the NEW schema? ==="
kc "$WS" get apibinding -o jsonpath='{range .items[?(@.spec.reference.export.name=="trust.ai-trust.msp")]}{.metadata.name}{" phase="}{.status.phase}{" schema="}{.status.boundResources[0].schema.name}{"\n"}{end}' 2>&1 | grep -av memcache
echo "=== restart the graphql gateway + listener so they rebuild the schema ==="
sk -n "$MESH_NS" rollout restart deploy/kubernetes-graphql-gateway deploy/kubernetes-graphql-gateway-listener 2>&1 | grep -av memcache
sk -n "$MESH_NS" rollout status deploy/kubernetes-graphql-gateway --timeout=120s 2>&1 | grep -av memcache | tail -1
sk -n "$MESH_NS" rollout status deploy/kubernetes-graphql-gateway-listener --timeout=120s 2>&1 | grep -av memcache | tail -1
sleep 20
echo "=== gateway logs: any remaining undefined/aitrust schema errors? ==="
sk -n "$MESH_NS" logs deploy/kubernetes-graphql-gateway-listener --tail=120 2>&1 | grep -av memcache | grep -iE 'aitrust|trust.ai|undefined|error.*schema|invalid' | tail -8
echo "(no aitrust errors above = schema built clean)"
echo "=== restart portal too (its GraphQL client cache) ==="
sk -n "$MESH_NS" rollout restart deploy/portal 2>&1 | grep -av memcache
