#!/bin/bash
exec > /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP/.state/poca504.out 2>&1
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
[ -s "$SHOOT_KUBECONFIG" ] || mint_shoot_kubeconfig || { echo LOGIN_EXPIRED; exit 3; }
export KUBECONFIG="$SHOOT_KUBECONFIG"
kubectl get ns >/dev/null 2>&1 || { echo LOGIN_EXPIRED; exit 3; }
SUF="ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu"
LB=130.214.18.166; GWNS=platform-mesh-system
NS="aitp-wzw3g7znvmqdk5qf-pocaitrust"
H="wzw3g7znvmqdk5qf-pocaitrust.$SUF"

echo "############ 1. instance namespace + ALL pod states (504 = backend not answering) ############"
kubectl get ns "$NS" 2>&1 | grep -avi memcache
echo "-- pods --"
kubectl -n "$NS" get pods -o wide 2>&1 | grep -avi memcache
echo "-- not Running/Completed --"
kubectl -n "$NS" get pods --no-headers 2>&1 | grep -avi memcache | grep -vE 'Running|Completed' || echo "  (all Running)"

echo
echo "############ 2. oauth2-proxy + shell (the entry backends the route points to) ############"
kubectl -n "$NS" get deploy oauth2-proxy shell -o wide 2>&1 | grep -avi memcache
echo "-- oauth2-proxy recent logs --"
kubectl -n "$NS" logs deploy/oauth2-proxy --tail=25 2>&1 | grep -avi memcache | tail -20
echo "-- oauth2-proxy pod events / restarts --"
kubectl -n "$NS" get pods -l app=oauth2-proxy -o jsonpath='{range .items[*]}{.metadata.name}{" restarts="}{.status.containerStatuses[0].restartCount}{" ready="}{.status.containerStatuses[0].ready}{" phase="}{.status.phase}{"\n"}{end}' 2>&1 | grep -avi memcache

echo
echo "############ 3. HTTPRoutes for this host — programmed + backendRefs resolve? ############"
for r in "$NS-app" "$NS-keycloak"; do
  echo "-- $r --"
  kubectl -n "$GWNS" get httproute "$r" -o jsonpath='parent={.spec.parentRefs[0].sectionName} host={.spec.hostnames[0]} backend={.spec.rules[0].backendRefs[0].name}:{.spec.rules[0].backendRefs[0].port} ns={.spec.rules[0].backendRefs[0].namespace}{"\n"}accepted={.status.parents[0].conditions[?(@.type=="Accepted")].status} resolved={.status.parents[0].conditions[?(@.type=="ResolvedRefs")].status}{"\n"}' 2>&1 | grep -avi memcache
done
echo "-- ReferenceGrant in the instance ns (gateway->svc cross-ns) --"
kubectl -n "$NS" get referencegrant 2>&1 | grep -avi memcache | head

echo
echo "############ 4. can we reach oauth2-proxy svc IN-CLUSTER (isolate gateway vs backend)? ############"
kubectl -n "$NS" run probe-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet --command -- \
  sh -c "curl -sS -m 8 http://oauth2-proxy.$NS.svc.cluster.local:8080/ping -o /dev/null -w 'oauth2-proxy /ping: http=%{http_code}\n' 2>&1 || echo 'in-cluster curl failed'" 2>&1 | grep -avi memcache | grep -E 'http=|failed'

echo
echo "############ 5. external via gateway (the 504 path) ############"
kubectl -n "$GWNS" run e-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet --command -- \
  sh -c "curl -skS -m 15 --resolve $H:443:$LB https://$H/ -o /dev/null -w 'ext https://host/ : http=%{http_code} time=%{time_total}s\n' 2>&1" 2>&1 | grep -avi memcache | grep -E 'http=|time'

echo
echo "############ 6. node the instance is on — is it under pressure / NotReady? ############"
kubectl -n "$NS" get pods -o wide --no-headers 2>&1 | grep -avi memcache | awk '{print $7}' | sort -u | head
kubectl top nodes 2>&1 | grep -avi memcache | grep -E 'NAME|msp-at' | head
echo DONE
