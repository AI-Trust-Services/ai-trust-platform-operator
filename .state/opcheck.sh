#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
echo "=== operator deploy image + env ==="
kubectl -n "$NS" get deploy aitrust-mt-operator -o jsonpath='image={.spec.template.spec.containers[0].image}{"\n"}' 2>&1 | grep -avi memcache
kubectl -n "$NS" get deploy aitrust-mt-operator -o jsonpath='{range .spec.template.spec.containers[0].env[*]}{.name}={.value}{"\n"}{end}' 2>&1 | grep -avi memcache
echo "=== operator serviceaccount + clusterrole rules (what can it create?) ==="
SA=$(kubectl -n "$NS" get deploy aitrust-mt-operator -o jsonpath='{.spec.template.spec.serviceAccountName}' 2>&1 | grep -avi memcache)
echo "sa: $SA"
CRB=$(kubectl get clusterrolebinding 2>/dev/null | grep -avi memcache | grep -iE "aitrust-mt|operator" | awk '{print $1}' | head)
echo "crbindings: $CRB"
for c in $CRB; do
  ROLE=$(kubectl get clusterrolebinding "$c" -o jsonpath='{.roleRef.name}' 2>/dev/null | grep -avi memcache)
  echo "--- role $ROLE rules ---"
  kubectl get clusterrole "$ROLE" -o jsonpath='{range .rules[*]}{.apiGroups}{" "}{.resources}{" -> "}{.verbs}{"\n"}{end}' 2>&1 | grep -avi memcache | head -20
done
echo DONE
