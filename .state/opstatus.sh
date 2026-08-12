#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
NS=aitp-q3c0weh7suf5hgjk-my-aitrust
echo "=== operator: is it still reconciling? (last 12 non-stack lines) ==="
sk -n aitrust-msp logs deploy/aitrust-msp-operator --tail=80 2>&1 | grep -av memcache \
  | grep -ivE '/src/main|controller-runtime@|sigs.k8s.io|processNextWorkItem|reconcileHandler|Start.func|\.Reconcile$|main\.\(\*reconciler\)\.fail' | tail -12
echo "=== operator restart count / age ==="
sk -n aitrust-msp get pods -l app.kubernetes.io/name=aitrust-msp-operator 2>&1 | grep -av memcache
echo "=== the SHOOT-side CR (what the operator actually reconciles + writes) ==="
sk get aitrustplatforminstance -A 2>&1 | grep -av memcache
echo "=== its status directly ==="
sk -n "$NS" get aitrustplatforminstance --ignore-not-found -o jsonpath='{range .items[*]}{.metadata.name}{" phase="}{.status.phase}{" ready="}{.status.ready}{"\n"}{end}' 2>&1 | grep -av memcache
