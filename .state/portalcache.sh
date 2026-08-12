#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
echo "=== does the portal cache a compiled schema file per cluster? check gateway schema store ==="
# The gateway-listener writes schema files; the gateway serves them. Check the served schema for the
# PROVIDER cluster still has stale/empty entry (the '1xwk2itxtl8w7vm0' schema-not-found earlier).
sk -n "$MESH_NS" logs deploy/kubernetes-graphql-gateway-listener --since=15m 2>&1 | grep -av memcache \
  | grep -iE '1xwk2|ai-trust|Schema (file updated|unchanged)|Generating' | tail -12
echo ""
echo "=== restart gateway ONCE more + confirm no schema-not-found after ==="
sk -n "$MESH_NS" rollout restart deploy/kubernetes-graphql-gateway 2>&1 | grep -av memcache
sk -n "$MESH_NS" rollout status deploy/kubernetes-graphql-gateway --timeout=120s 2>&1 | grep -av memcache | tail -1
sleep 15
sk -n "$MESH_NS" logs deploy/kubernetes-graphql-gateway --since=1m 2>&1 | grep -av memcache | grep -iE 'schema not found|error' | tail -5
echo "(empty=clean)"
