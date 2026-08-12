#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
NS=aitp-q3c0weh7suf5hgjk-my-aitrust
echo "=== bump rabbitmq readiness probe timeout 1s->5s (probe was false-negative on a busy node) ==="
sk -n "$NS" patch deploy rabbitmq --type=json -p '[{"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/timeoutSeconds","value":5},{"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/periodSeconds","value":15}]' 2>&1 | grep -av memcache
sk -n "$NS" rollout status deploy/rabbitmq --timeout=120s 2>&1 | grep -av memcache | tail -2
echo "=== all deploys now ==="
sk -n "$NS" get deploy --no-headers 2>&1 | grep -av memcache | awk '$2!="1/1"{print "NOT READY:",$1,$2}'; echo "(nothing above = all ready)"
echo "=== wait for operator Ready flip (RequeueAfter 20s) ==="
setup_kcp >/dev/null 2>&1; kcp_portforward >/dev/null 2>&1; trap 'pkill -f "port-forward.*root-proxy.*6443" 2>/dev/null||true' EXIT
for i in $(seq 1 8); do
  P=$(kc "root:orgs:$ORG_NAME:$ACCOUNT_NAME" -n default get aitrustplatforminstance "$INSTANCE_NAME" -o jsonpath='{.status.phase}/{.status.ready}' 2>/dev/null)
  echo "  status=$P"
  [ "$P" = "Ready/true" ] && { echo "READY"; break; }
  sleep 20
done
kc "root:orgs:$ORG_NAME:$ACCOUNT_NAME" -n default get aitrustplatforminstance "$INSTANCE_NAME" -o jsonpath='phase={.status.phase} ready={.status.ready} url={.status.url}{"\n"}' 2>&1 | grep -av memcache
