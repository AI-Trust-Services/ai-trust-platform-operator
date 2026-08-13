#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=bayq7srx101gga1s
echo "=== FULL mirrored CR (all metadata: labels, annotations, ownerRefs) ==="
kubectl -n "$NS" get subscriptions.sub.aitrustmt.msp mttest2 -o jsonpath='{.metadata}{"\n"}' 2>&1 | grep -avi memcache | tr ',' '\n' | head -40
echo "=== the mirror NAMESPACE labels/annotations (does it carry org/path?) ==="
kubectl get ns "$NS" -o jsonpath='{.metadata.labels}{"\n"}{.metadata.annotations}{"\n"}' 2>&1 | grep -avi memcache | tr ',' '\n' | grep -iE 'kcp|org|path|cluster|account|workspace' | head -20
echo "=== any APIExportEndpointSlice / kcp cluster mapping on the shoot? ==="
kubectl get ns "$NS" -o yaml 2>&1 | grep -avi memcache | grep -iE 'kcp.io|path|org|workspace|cluster' | head -20
echo DONE
