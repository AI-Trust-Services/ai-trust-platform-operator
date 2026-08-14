#!/bin/bash
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh 2>/dev/null; load_config 2>/dev/null
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
f(){ grep -avi memcache; }

echo "===== roll operator to v10 ====="
kubectl -n "$NS" set image deploy/aitrust-mt-operator operator="$OPERATOR_IMAGE:$OPERATOR_TAG" 2>&1 | f
kubectl -n "$NS" rollout status deploy/aitrust-mt-operator --timeout=120s 2>&1 | f | tail -1

echo; echo "===== roll shell (front-channel logout href) ====="
kubectl -n "$NS" rollout restart deploy/shell 2>&1 | f
kubectl -n "$NS" rollout status deploy/shell --timeout=120s 2>&1 | f | tail -1

echo; echo "===== re-stamp ready tenants: delete oauth2-proxy deploy so operator recreates with --whitelist-domain ====="
for ORG in fridaytest livedemo mirceatest mttest2 sohan; do
  kubectl -n "$NS" delete deploy "oauth2-proxy-$ORG" --ignore-not-found >/dev/null 2>&1
  kubectl -n "$NS" delete job "kc-client-$ORG" --ignore-not-found >/dev/null 2>&1
  SUB=$(kubectl get subscriptions.sub.aitrustmt.msp -A -o jsonpath='{range .items[?(@.spec.org=="'"$ORG"'")]}{.metadata.namespace}/{.metadata.name}{"\n"}{end}' 2>/dev/null | grep -avi memcache | head -1)
  [ -n "$SUB" ] && kubectl -n "${SUB%%/*}" annotate subscriptions.sub.aitrustmt.msp "${SUB##*/}" restamp=v10 --overwrite >/dev/null 2>&1 && echo "  nudged $ORG"
done

echo; echo "===== wait 40s, verify proxies recreated WITH --whitelist-domain ====="
sleep 40
for ORG in fridaytest livedemo mirceatest mttest2 sohan; do
  WL=$(kubectl -n "$NS" get deploy "oauth2-proxy-$ORG" -o jsonpath='{range .spec.template.spec.containers[0].args[*]}{@}{"\n"}{end}' 2>/dev/null | grep -avi memcache | grep -c 'whitelist-domain' || echo 0)
  RD=$(kubectl -n "$NS" get pods -l org="$ORG",app=oauth2-proxy-org --no-headers 2>/dev/null | grep -avi memcache | tail -1)
  echo "  $ORG: whitelist-domain flags=$WL  pod: $RD"
done
echo DONE
