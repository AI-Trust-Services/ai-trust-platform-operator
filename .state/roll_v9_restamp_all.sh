#!/bin/bash
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh 2>/dev/null; load_config 2>/dev/null
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
f(){ grep -avi memcache; }

echo "===== roll operator to v9 ====="
kubectl -n "$NS" set image deploy/aitrust-mt-operator operator="$OPERATOR_IMAGE:$OPERATOR_TAG" 2>&1 | f
kubectl -n "$NS" rollout status deploy/aitrust-mt-operator --timeout=120s 2>&1 | f | tail -1

echo; echo "===== re-stamp all READY tenants: delete kc-client Job + nudge subscription ====="
# Ready orgs from the earlier list (skip Degraded berlin/test2-org which have no realm)
for ORG in fridaytest livedemo mirceatest mttest2 sohan; do
  kubectl -n "$NS" delete job "kc-client-$ORG" --ignore-not-found >/dev/null 2>&1
  SUB=$(kubectl get subscriptions.sub.aitrustmt.msp -A -o jsonpath='{range .items[?(@.spec.org=="'"$ORG"'")]}{.metadata.namespace}/{.metadata.name}{"\n"}{end}' 2>/dev/null | grep -avi memcache | head -1)
  if [ -n "$SUB" ]; then
    SNS="${SUB%%/*}"; SNAME="${SUB##*/}"
    kubectl -n "$SNS" annotate subscriptions.sub.aitrustmt.msp "$SNAME" restamp=v9 --overwrite >/dev/null 2>&1
    echo "  nudged $ORG ($SUB)"
  fi
done

echo; echo "===== wait ~40s, then check each kc-client job + client attribute ====="
sleep 40
KCU=$(kubectl -n "$NS" get secret mesh-keycloak-admin -o jsonpath='{.data.username}' | base64 -d)
KCP=$(kubectl -n "$NS" get secret mesh-keycloak-admin -o jsonpath='{.data.password}' | base64 -d)
for ORG in fridaytest livedemo mirceatest mttest2 sohan; do
  J=$(kubectl -n "$NS" get job "kc-client-$ORG" -o jsonpath='{.status.succeeded}' 2>/dev/null | grep -avi memcache)
  echo "  kc-client-$ORG succeeded=$J"
done
echo "-- verify post.logout attribute on each client --"
INNER='K=/opt/keycloak/bin/kcadm.sh
$K config credentials --server http://localhost:8080/keycloak --realm master --user "$U" --password "$P" >/dev/null 2>&1
for R in fridaytest livedemo mirceatest mttest2 sohan; do
  CID=$($K get clients -r $R -q clientId=aitrust-mt-app --fields id --format csv --noquotes 2>/dev/null | head -1)
  A=$($K get clients/$CID -r $R --fields attributes 2>/dev/null | tr -d " \n")
  echo "  $R: $A"
done'
kubectl -n platform-mesh-system exec -i keycloak-0 -- env U="$KCU" P="$KCP" sh -c "$INNER" 2>&1 | f
echo DONE
