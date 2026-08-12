#!/bin/bash
exec > /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP/.state/ha-final.out 2>&1
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
kubectl get ns >/dev/null 2>&1 || { echo LOGIN_EXPIRED; exit 3; }
NS=aitp-q3c0weh7suf5hgjk-my-aitrust

echo "==== converge my-aitrust: scale to 2 + set rolling strategy (correct patch types) ===="
# replicas + strategy via strategic merge (no container image needed at this level)
kubectl -n "$NS" patch deploy oauth2-proxy -p '{"spec":{"replicas":2,"strategy":{"type":"RollingUpdate","rollingUpdate":{"maxUnavailable":0,"maxSurge":1}}}}' 2>&1 | grep -avi memcache
kubectl -n "$NS" patch deploy shell        -p '{"spec":{"replicas":2,"strategy":{"type":"RollingUpdate","rollingUpdate":{"maxUnavailable":0,"maxSurge":1}}}}' 2>&1 | grep -avi memcache
kubectl -n "$NS" rollout status deploy/oauth2-proxy --timeout=120s 2>&1 | grep -avi memcache | tail -1
kubectl -n "$NS" rollout status deploy/shell        --timeout=120s 2>&1 | grep -avi memcache | tail -1

echo
echo "==== FINAL: all instances 2/2 + strategy maxUnavailable=0 ===="
for NS in $(kubectl get ns -o name 2>/dev/null | grep -avi memcache | grep -oE 'aitp-[a-z0-9-]+'); do
  kubectl -n "$NS" get deploy oauth2-proxy >/dev/null 2>&1 || continue
  echo -n "  $NS: "
  kubectl -n "$NS" get deploy oauth2-proxy shell -o jsonpath='oauth2={.items[0].status.readyReplicas}/{.items[0].spec.replicas}(mu={.items[0].spec.strategy.rollingUpdate.maxUnavailable}) shell={.items[1].status.readyReplicas}/{.items[1].spec.replicas}(mu={.items[1].spec.strategy.rollingUpdate.maxUnavailable}){"\n"}' 2>&1 | grep -avi memcache
done
echo DONE
