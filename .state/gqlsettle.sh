#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
echo "=== gateway-listener: aitrust schema errors settled? (last 80) ==="
sk -n "$MESH_NS" logs deploy/kubernetes-graphql-gateway-listener --tail=80 2>&1 | grep -av memcache | grep -iE 'aitrust|trust.ai|schema not found|undefined' | tail -6
echo "(empty above = settled)"
echo "=== gateway main: create/schema error for trust.ai? ==="
sk -n "$MESH_NS" logs deploy/kubernetes-graphql-gateway --tail=100 2>&1 | grep -av memcache | grep -iE 'aitrust|trust.ai|undefined' | tail -6
echo "=== is the AITrust type in the gateway's schema now? (grep the reconciled schema log) ==="
sk -n "$MESH_NS" logs deploy/kubernetes-graphql-gateway-listener --tail=200 2>&1 | grep -av memcache | grep -iE 'AITrustPlatformInstance|aitrustplatforminstances' | tail -4
