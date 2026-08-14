#!/bin/bash
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh 2>/dev/null; load_config 2>/dev/null
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
f(){ grep -avi memcache; }

echo "===== 1) ALL Subscription CRs (name / org / phase / message) ====="
kubectl get subscriptions.sub.aitrustmt.msp -A -o jsonpath='{range .items[*]}ns={.metadata.namespace}  name={.metadata.name}  org={.spec.org}  phase={.status.phase}  msg={.status.conditions[0].message}{"\n"}{end}' 2>&1 | f

echo; echo "===== 2) per-org resources for org=fridaytest AND org=testfriday ====="
for O in fridaytest testfriday; do
  echo "--- org=$O ---"
  kubectl -n "$NS" get deploy,svc,job -l org="$O" --no-headers 2>&1 | f || echo "  (no deploy/svc/job)"
  kubectl -n "$NS" get secret 2>&1 | f | grep -iE "oauth2-$O" || echo "  (no oauth2 secret)"
  kubectl -n platform-mesh-system get httproute "aitrust-mt-$O" --no-headers 2>&1 | f || echo "  (no httproute)"
done

echo; echo "===== 3) mesh-keycloak-admin secret + keycloak pod ====="
U=$(kubectl -n "$NS" get secret mesh-keycloak-admin -o jsonpath='{.data.username}' 2>/dev/null | base64 -d)
[ -z "$U" ] && echo "  (mesh-keycloak-admin secret not found in $NS)" || echo "  admin-user present: yes"
POD=$(kubectl -n platform-mesh-system get pod -o name 2>/dev/null | grep -i keycloak | head -1 | sed 's#pod/##')
echo "  keycloak pod: ${POD:-NONE}"

echo; echo "===== 4) operator image (v6?) + pod ====="
kubectl -n "$NS" get deploy aitrust-mt-operator -o jsonpath='image={.spec.template.spec.containers[0].image}{"\n"}' 2>&1 | f
kubectl -n "$NS" get pods -l app=aitrust-mt-operator -o wide --no-headers 2>&1 | f

echo; echo "===== 5) operator log — fridaytest/testfriday/realm/Degraded ====="
kubectl -n "$NS" logs deploy/aitrust-mt-operator --tail=250 2>&1 | f | grep -iE 'fridaytest|testfriday|realm|degraded|provision|ready|reconcil' | tail -40

echo; echo "===== 6) shared app backends present? ====="
kubectl -n "$NS" get deploy --no-headers 2>&1 | f | grep -iE 'compliance|users|backend|shell|portal|nginx'
echo DONE
