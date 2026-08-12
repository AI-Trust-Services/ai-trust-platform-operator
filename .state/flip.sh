#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
NS=aitp-q3c0weh7suf5hgjk-my-aitrust
WS="root:orgs:$ORG_NAME:$ACCOUNT_NAME"
echo "=== rabbitmq + any not-ready ==="
sk -n "$NS" get deploy --no-headers 2>&1 | grep -av memcache | awk '$2!="1/1"{print "NOT READY:",$1,$2}'; echo "(all ready if nothing above)"
echo "=== nudge the SHOOT-side mirrored CR (correct ns) ==="
CRNS=$(sk get aitrustplatforminstance -A -o jsonpath='{.items[0].metadata.namespace}' 2>/dev/null)
CRNAME=$(sk get aitrustplatforminstance -A -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
echo "shoot CR = $CRNS/$CRNAME"
sk -n "$CRNS" annotate aitrustplatforminstance "$CRNAME" nudge="$(date +%s)" --overwrite 2>&1 | grep -av memcache
setup_kcp >/dev/null 2>&1; kcp_portforward >/dev/null 2>&1; trap 'pkill -f "port-forward.*root-proxy.*6443" 2>/dev/null||true' EXIT
for i in $(seq 1 10); do
  P=$(kc "$WS" -n default get aitrustplatforminstance my-aitrust -o jsonpath='{.status.phase}/{.status.ready}' 2>/dev/null)
  echo "  consumer status=$P"; [ "$P" = "Ready/true" ] && { echo ">>> READY <<<"; break; }; sleep 18
done
