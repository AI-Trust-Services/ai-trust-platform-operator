#!/bin/bash
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh 2>/dev/null; load_config 2>/dev/null
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
f(){ grep -avi memcache; }

STORE=01KZX8TV6TMMF3G3F9DTE87YV4
FGA=http://openfga.platform-mesh-system.svc.cluster.local:8080

echo "===== spec of the fridaytest subscription 'r' (adminEmail present?) ====="
kubectl -n 1nqv0yinuy04ph1b get subscriptions.sub.aitrustmt.msp r -o jsonpath='{.spec}{"\n"}' 2>&1 | f

echo; echo "===== spec of a WORKING one: mirceatest (mttest3) ====="
kubectl -n 1p2gonssnyvy9nhe get subscriptions.sub.aitrustmt.msp mttest3 -o jsonpath='{.spec}{"\n"}' 2>&1 | f

echo; echo "===== ALL tuples in the shared OpenFGA store (throwaway curl pod) ====="
kubectl -n "$NS" run fga-read-$$ --rm -i --restart=Never --image=curlimages/curl:8.10.1 --quiet -- \
  -s -X POST "$FGA/stores/$STORE/read" -H 'content-type: application/json' -d '{}' 2>&1 | f
echo
echo DONE
