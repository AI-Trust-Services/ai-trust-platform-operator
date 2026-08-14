#!/bin/bash
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh 2>/dev/null; load_config 2>/dev/null
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
f(){ grep -avi memcache; }

ORG=fridaytest
echo "===== re-stamp $ORG: delete kc-client Job + oauth2-proxy so operator recreates from v7 templates ====="
kubectl -n "$NS" delete job "kc-client-$ORG" --ignore-not-found 2>&1 | f
kubectl -n "$NS" delete deploy "oauth2-proxy-$ORG" --ignore-not-found 2>&1 | f
kubectl -n "$NS" delete svc "oauth2-proxy-$ORG" --ignore-not-found 2>&1 | f
# HTTPRoute lives in the gateway ns; leave it (operator recreates proxy+svc; route still points to svc name)

echo "  nudge the $ORG subscription to reconcile now (bump an annotation)"
# find the subscription for org=fridaytest
SUB=$(kubectl get subscriptions.sub.aitrustmt.msp -A -o jsonpath='{range .items[?(@.spec.org=="'"$ORG"'")]}{.metadata.namespace}/{.metadata.name}{"\n"}{end}' 2>/dev/null | head -1)
echo "  subscription: $SUB"
if [ -n "$SUB" ]; then
  SNS="${SUB%%/*}"; SNAME="${SUB##*/}"
  kubectl -n "$SNS" annotate subscriptions.sub.aitrustmt.msp "$SNAME" restamp="v7-$(date +%s 2>/dev/null || echo now)" --overwrite 2>&1 | f || \
  kubectl -n "$SNS" annotate subscriptions.sub.aitrustmt.msp "$SNAME" restamp=v7 --overwrite 2>&1 | f
fi

echo; echo "===== wait ~30s for operator to re-stamp, then verify ====="
sleep 30
echo "-- kc-client-$ORG Job (should be recreated + complete) --"
kubectl -n "$NS" get job "kc-client-$ORG" --no-headers 2>&1 | f || echo "  (not yet)"
echo "-- kc-client-$ORG Job log (client updated with post-logout?) --"
kubectl -n "$NS" logs job/"kc-client-$ORG" --tail=15 2>&1 | f | grep -iE 'updated|created|post|done|exists' | tail -6
echo "-- oauth2-proxy-$ORG backend-logout-url (should have id_token_hint) --"
kubectl -n "$NS" get deploy "oauth2-proxy-$ORG" -o jsonpath='{range .spec.template.spec.containers[0].args[*]}{@}{"\n"}{end}' 2>&1 | f | grep -i 'backend-logout' | sed 's/^/    /'
echo DONE
