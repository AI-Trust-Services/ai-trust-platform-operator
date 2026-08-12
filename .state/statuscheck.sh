#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
NS=aitp-q3c0weh7suf5hgjk-my-aitrust
echo "=== all deploys ready count ==="
sk -n "$NS" get deploy --no-headers 2>&1 | grep -av memcache | awk '{print $1, $2}' | tail -30
echo "=== operator log tail (errors only, newest) ==="
sk -n aitrust-msp logs deploy/aitrust-msp-operator --tail=50 2>&1 | grep -av memcache \
  | grep -iE 'error|failed' | grep -ivE '/src/main|controller-runtime@|sigs.k8s.io' | tail -6
echo "=== shoot-side (mirrored) CR status ==="
sk -n "$NS" get aitrustplatforminstance my-aitrust -o jsonpath='phase={.status.phase} ready={.status.ready} url={.status.url}{"\n"}' 2>&1 | grep -av memcache
