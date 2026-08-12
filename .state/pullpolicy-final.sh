#!/bin/bash
exec > /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP/.state/pullpolicy-final.out 2>&1
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
kubectl get ns >/dev/null 2>&1 || { echo LOGIN_EXPIRED; exit 3; }
SUF="ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu"; LB=130.214.18.166
sleep 30
echo "==== all instances settled? (not-ready should be 0) ===="
for NS in $(kubectl get ns -o name 2>/dev/null | grep -avi memcache | grep -oE 'aitp-[a-z0-9-]+'); do
  bad=$(kubectl -n "$NS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep -vE 'Running|Completed' | wc -l)
  echo "  $NS: not-ready=$bad"
done
echo
echo "==== external reachability (all should be 200/403, no 504) ===="
for NS in $(kubectl get ns -o name 2>/dev/null | grep -avi memcache | grep -oE 'aitp-[a-z0-9-]+'); do
  H=$(echo "$NS" | sed 's/^aitp-//').$SUF
  kubectl -n platform-mesh-system run z-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet --command -- \
    sh -c "curl -skS -m 12 --resolve $H:443:$LB https://$H/ -o /dev/null -w '$H http=%{http_code}\n'" 2>&1 | grep -avi memcache | grep http=
done
echo
echo "==== count Always across all instance app deploys (should be uniform) ===="
for NS in $(kubectl get ns -o name 2>/dev/null | grep -avi memcache | grep -oE 'aitp-[a-z0-9-]+'); do
  n=$(kubectl -n "$NS" get deploy -o jsonpath='{range .items[*]}{.spec.template.spec.containers[0].imagePullPolicy}{"\n"}{end}' 2>/dev/null | grep -avi memcache | grep -c Always)
  echo "  $NS: deploys with Always = $n"
done
echo DONE
