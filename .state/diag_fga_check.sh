#!/bin/bash
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh 2>/dev/null; load_config 2>/dev/null
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
f(){ grep -avi memcache; }

STORE=01KZX8TV6TMMF3G3F9DTE87YV4
FGA=http://openfga.platform-mesh-system.svc.cluster.local:8080

echo "===== store id the users-backend actually uses (env + /config file) ====="
kubectl -n "$NS" get deploy users-backend -o jsonpath='OPENFGA_STORE_ID(env)={range .spec.template.spec.containers[0].env[?(@.name=="OPENFGA_STORE_ID")]}{.value}{end}{"\n"}' 2>&1 | f
kubectl -n "$NS" exec deploy/users-backend -- sh -c 'cat /config/store_id 2>/dev/null || echo "(no /config/store_id file)"' 2>&1 | f

echo; echo "===== authorization models in the store (is there a model? which id?) ====="
kubectl -n "$NS" run fgacheck1-$$ --rm -i --restart=Never --image=curlimages/curl:8.10.1 --quiet --command -- \
  sh -c "curl -s $FGA/stores/$STORE/authorization-models | sed 's/,/,\n/g' | grep -iE 'id|schema_version' | head -8" 2>&1 | f

echo; echo "===== the EXACT check the backend runs: user:mircea.craciun@sap.com can_read_systems platform:global ====="
kubectl -n "$NS" run fgacheck2-$$ --rm -i --restart=Never --image=curlimages/curl:8.10.1 --quiet --command -- \
  sh -c "curl -s -X POST $FGA/stores/$STORE/check -H 'content-type: application/json' -d '{\"tuple_key\":{\"user\":\"user:mircea.craciun@sap.com\",\"relation\":\"can_read_systems\",\"object\":\"platform:global\"}}'" 2>&1 | f

echo; echo "===== users-backend: EXACT body of a /me/permissions response (log line already 200 — capture status via in-cluster call with the proxy-set header) ====="
kubectl -n "$NS" exec deploy/users-backend -- sh -c 'curl -s -o /dev/null -w "status=%{http_code}\n" -H "X-Forwarded-Preferred-Username: mircea.craciun@sap.com" http://localhost:8000/v1/me/permissions 2>/dev/null || curl -s -H "X-Forwarded-Preferred-Username: mircea.craciun@sap.com" http://localhost:8001/v1/me/permissions' 2>&1 | f
echo "--- and the actual JSON body ---"
kubectl -n "$NS" exec deploy/users-backend -- sh -c 'for p in 8000 8001 8002 80; do curl -s -H "X-Forwarded-Preferred-Username: mircea.craciun@sap.com" http://localhost:$p/v1/me/permissions && echo " <- port $p" && break; done' 2>&1 | f
echo DONE
