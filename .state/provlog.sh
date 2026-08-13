#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
echo "=== why prov-38ef9l9wvvoacrsm-pocmt crashloops (its pod logs) ==="
PP=$(kubectl -n "$NS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep 'prov-38ef9' | awk '{print $1}' | head -1)
echo "pod: $PP"
[ -n "$PP" ] && kubectl -n "$NS" logs "$PP" --tail=20 2>&1 | grep -avi memcache | tail -20
echo "=== what image + env does the prov job use (is it the old keycloak-provision path?) ==="
kubectl -n "$NS" get job prov-38ef9l9wvvoacrsm-pocmt -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}{range .spec.template.spec.containers[0].env[*]}{.name}={.value}{"\n"}{end}' 2>&1 | grep -avi memcache | head -15
echo "=== which operator image is actually running? ==="
kubectl -n "$NS" get deploy aitrust-mt-operator -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}' 2>&1 | grep -avi memcache
echo DONE
