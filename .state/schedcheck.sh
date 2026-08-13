#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
echo "=== how does a running backend schedule? nodeSelector + tolerations ==="
kubectl -n "$NS" get deploy ai-system-registry-backend -o jsonpath='nodeSelector={.spec.template.spec.nodeSelector}{"\n"}tolerations={.spec.template.spec.tolerations}{"\n"}' 2>&1 | grep -avi memcache
echo "=== the node + its taints/labels ==="
kubectl get nodes -l "$MSP_WORKER_LABEL=true" --no-headers 2>&1 | grep -avi memcache | awk '{print $1}'
N=$(kubectl get nodes -l "$MSP_WORKER_LABEL=true" --no-headers 2>/dev/null | grep -avi memcache | awk '{print $1}' | head -1)
echo "node: $N"
kubectl get node "$N" -o jsonpath='taints={.spec.taints}{"\n"}' 2>&1 | grep -avi memcache
echo DONE
