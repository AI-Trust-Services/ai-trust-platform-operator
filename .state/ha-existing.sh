#!/bin/bash
exec > /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP/.state/ha-existing.out 2>&1
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
kubectl get ns >/dev/null 2>&1 || { echo LOGIN_EXPIRED; exit 3; }
LB=130.214.18.166; SUF="ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu"

# strategic-merge patch: strategy + readinessProbe + replicas, per deploy
patch_ha(){
  local ns="$1" dep="$2" probePath="$3" probePort="$4" cname="$5"
  kubectl -n "$ns" patch deploy "$dep" --type=merge -p "{
    \"spec\":{\"replicas\":2,
      \"strategy\":{\"type\":\"RollingUpdate\",\"rollingUpdate\":{\"maxUnavailable\":0,\"maxSurge\":1}},
      \"template\":{\"spec\":{\"containers\":[{\"name\":\"$cname\",
        \"readinessProbe\":{\"httpGet\":{\"path\":\"$probePath\",\"port\":$probePort},\"initialDelaySeconds\":3,\"periodSeconds\":5}}]}}}}" 2>&1 | grep -avi memcache | sed "s/^/  [$ns\/$dep] /"
}

for NS in $(kubectl get ns -o name 2>/dev/null | grep -avi memcache | grep -oE 'aitp-[a-z0-9-]+'); do
  kubectl -n "$NS" get deploy oauth2-proxy >/dev/null 2>&1 || continue
  echo "==== $NS ===="
  patch_ha "$NS" oauth2-proxy /ping 4180 oauth2-proxy
  patch_ha "$NS" shell / 80 shell
done

echo
echo "==== wait for all rollouts ===="
for NS in $(kubectl get ns -o name 2>/dev/null | grep -avi memcache | grep -oE 'aitp-[a-z0-9-]+'); do
  kubectl -n "$NS" get deploy oauth2-proxy >/dev/null 2>&1 || continue
  kubectl -n "$NS" rollout status deploy/oauth2-proxy --timeout=150s 2>&1 | grep -avi memcache | tail -1 | sed "s/^/  [$NS oauth2] /"
  kubectl -n "$NS" rollout status deploy/shell        --timeout=150s 2>&1 | grep -avi memcache | tail -1 | sed "s/^/  [$NS shell ] /"
done

echo
echo "==== verify: each instance now has 2/2 oauth2-proxy + 2/2 shell ===="
for NS in $(kubectl get ns -o name 2>/dev/null | grep -avi memcache | grep -oE 'aitp-[a-z0-9-]+'); do
  kubectl -n "$NS" get deploy oauth2-proxy >/dev/null 2>&1 || continue
  echo -n "  $NS: "; kubectl -n "$NS" get deploy oauth2-proxy shell -o jsonpath='oauth2={.items[0].status.readyReplicas}/{.items[0].status.replicas} shell={.items[1].status.readyReplicas}/{.items[1].status.replicas}{"\n"}' 2>&1 | grep -avi memcache
done

echo
echo "==== external reachability of each instance (403 fast = healthy sign-in gate) ===="
for NS in $(kubectl get ns -o name 2>/dev/null | grep -avi memcache | grep -oE 'aitp-[a-z0-9-]+'); do
  H=$(echo "$NS" | sed 's/^aitp-//').$SUF
  kubectl -n platform-mesh-system run x-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet --command -- \
    sh -c "curl -skS -m 12 --resolve $H:443:$LB https://$H/ -o /dev/null -w '$H http=%{http_code} t=%{time_total}s\n'" 2>&1 | grep -avi memcache | grep -E 'http='
done
echo DONE
