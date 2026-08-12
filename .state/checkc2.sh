#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config

echo "=== A. ANY 'undefined' anywhere in listener OR gateway (since 10m)? ==="
UL=$(sk -n "$MESH_NS" logs deploy/kubernetes-graphql-gateway-listener --since=10m 2>&1 | grep -av memcache | grep -ic 'undefined')
UG=$(sk -n "$MESH_NS" logs deploy/kubernetes-graphql-gateway --since=10m 2>&1 | grep -av memcache | grep -ic 'undefined')
echo "listener 'undefined' count = $UL ; gateway 'undefined' count = $UG"

echo
echo "=== B. LISTENER: lines for the aitrustg2:demo consumer + ai-trust provider (Generating/Schema file updated/Successfully reconciled around those paths) ==="
sk -n "$MESH_NS" logs deploy/kubernetes-graphql-gateway-listener --since=10m 2>&1 | grep -av memcache \
  | grep -iE 'aitrustg2|providers:ai-trust' | grep -iE 'Generating schema|Schema file updated|Schema unchanged|Successfully reconciled|Processing schema' | tail -40

echo
echo "=== C. LISTENER: is 'schema not found' also emitted for KNOWN-good clusters (control)? count of distinct clusters with the error ==="
sk -n "$MESH_NS" logs deploy/kubernetes-graphql-gateway-listener --since=10m 2>&1 | grep -av memcache \
  | grep 'schema not found' | grep -oE '"cluster": "[^"]+"' | sort -u | tail -40

echo
echo "=== D. GATEWAY: any ERROR loading/parsing/generating a schema (not the gRPC reconnect)? ==="
sk -n "$MESH_NS" logs deploy/kubernetes-graphql-gateway --since=10m 2>&1 | grep -av memcache \
  | grep -iE 'ERROR|failed' | grep -viE 'gRPC stream error, reconnecting|EOF|goaway' | tail -30
echo "--- (if empty above, no schema load/parse errors) ---"

echo
echo "=== E. GATEWAY: final load status specifically for aitrustg2:demo ==="
sk -n "$MESH_NS" logs deploy/kubernetes-graphql-gateway --since=10m 2>&1 | grep -av memcache \
  | grep 'aitrustg2:demo' | tail -6

echo
echo "=== F. LISTENER: 'Schema file updated' vs 'schema not found' — did any 'Schema file updated' fire for aitrustg2 paths after warmup? ==="
sk -n "$MESH_NS" logs deploy/kubernetes-graphql-gateway-listener --since=10m 2>&1 | grep -av memcache \
  | grep -E 'Schema file updated' | grep -iE 'aitrustg2|ai-trust' | tail -20
echo "--- (also show whether the LATEST reconcile pass still errors for aitrustg2:demo) ---"
sk -n "$MESH_NS" logs deploy/kubernetes-graphql-gateway-listener --since=10m 2>&1 | grep -av memcache \
  | grep 'aitrustg2:demo' | tail -8
