#!/bin/bash
exec > /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP/.state/ha-settle.out 2>&1
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
kubectl get ns >/dev/null 2>&1 || { echo LOGIN_EXPIRED; exit 3; }
LB=130.214.18.166; SUF="ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu"

echo "==== give the v8 operator a reconcile cycle to converge all instances (wait 60s) ===="
sleep 60

echo "==== steady-state replica counts (want 2/2 oauth2 + 2/2 shell, no stale 3rd) ===="
for NS in $(kubectl get ns -o name 2>/dev/null | grep -avi memcache | grep -oE 'aitp-[a-z0-9-]+'); do
  kubectl -n "$NS" get deploy oauth2-proxy >/dev/null 2>&1 || continue
  echo -n "  $NS: "
  kubectl -n "$NS" get deploy oauth2-proxy shell -o jsonpath='oauth2 spec={.items[0].spec.replicas} ready={.items[0].status.readyReplicas} | shell spec={.items[1].spec.replicas} ready={.items[1].status.readyReplicas} | oauth2-strategy={.items[0].spec.strategy.rollingUpdate.maxUnavailable}{"\n"}' 2>&1 | grep -avi memcache
  # any non-running oauth2/shell pods (stale replicasets)?
  bad=$(kubectl -n "$NS" get pods -l app=oauth2-proxy --no-headers 2>/dev/null | grep -avi memcache | grep -vE 'Running' | wc -l)
  [ "$bad" -gt 0 ] && kubectl -n "$NS" get pods -l app=oauth2-proxy --no-headers 2>&1 | grep -avi memcache | grep -vE 'Running' | sed 's/^/     stale: /'
done

echo
echo "==== LIVE 504 TEST: roll oauth2-proxy on pocaitrust while hammering the URL — expect NO 504 ===="
NS=aitp-wzw3g7znvmqdk5qf-pocaitrust
H=wzw3g7znvmqdk5qf-pocaitrust.$SUF
kubectl -n "$NS" rollout restart deploy/oauth2-proxy >/dev/null 2>&1
kubectl -n platform-mesh-system run hammer-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet --command -- \
  sh -c 'for i in $(seq 1 30); do curl -skS -m 5 --resolve '"$H"':443:'"$LB"' https://'"$H"'/ -o /dev/null -w "%{http_code} " 2>/dev/null; sleep 1; done; echo' 2>&1 | grep -avi memcache | tr ' ' '\n' | sort | uniq -c | sed 's/^/  /'
echo "  ^ (counts per HTTP code during a rollout; want NO 502/504)"
kubectl -n "$NS" rollout status deploy/oauth2-proxy --timeout=120s 2>&1 | grep -avi memcache | tail -1
echo DONE
