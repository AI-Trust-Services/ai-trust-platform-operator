#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
NS=q3c0weh7suf5hgjk
echo "=== touch the shoot-side CR to force a reconcile event ==="
sk -n "$NS" annotate aitrustplatforminstance my-aitrust reconcile-nudge="$(date +%s)" --overwrite 2>&1 | grep -av memcache
sleep 10
echo "=== operator logs after nudge ==="
sk -n aitrust-msp logs deploy/aitrust-msp-operator --tail=25 2>&1 | grep -av memcache \
  | grep -ivE '/src/main|controller-runtime@|sigs.k8s.io|processNextWorkItem|reconcileHandler|Start.func|\.Reconcile$|Starting (EventSource|Controller|workers)|metrics|operator starting' | tail -12
echo "=== shoot-side CR status now ==="
sk -n "$NS" get aitrustplatforminstance my-aitrust -o jsonpath='phase={.status.phase} ready={.status.ready}{"\n"}' 2>&1 | grep -av memcache
