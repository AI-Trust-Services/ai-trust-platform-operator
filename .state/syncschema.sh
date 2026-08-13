#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
echo "=== syncagent PublishedResource for Subscription (does it reflect the CRD)? ==="
kubectl get publishedresources.syncagent.kcp.io -A 2>&1 | grep -avi memcache | head
kubectl get publishedresources.syncagent.kcp.io -A -o jsonpath='{range .items[*]}{.metadata.name}: resource={.spec.resource}{"\n"}{end}' 2>&1 | grep -avi memcache | head
echo "=== restart syncagent to force re-publish the updated CRD schema (spec.org) ==="
kubectl -n "$NS" rollout restart deploy/aitrust-mt-syncagent 2>&1 | grep -avi memcache
kubectl -n "$NS" rollout status deploy/aitrust-mt-syncagent --timeout=90s 2>&1 | grep -avi memcache | tail -1
echo "=== syncagent logs (schema publish) ==="
kubectl -n "$NS" logs deploy/aitrust-mt-syncagent --tail=20 2>&1 | grep -avi memcache | grep -iE 'publish|schema|subscription|org|error|CRD' | head -12
echo DONE
