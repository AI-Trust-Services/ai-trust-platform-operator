#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
NS=aitp-q3c0weh7suf5hgjk-my-aitrust
WS="root:orgs:$ORG_NAME:$ACCOUNT_NAME"
echo "=== wait for all deploys Ready on the big node ==="
for i in $(seq 1 24); do
  NR=$(sk -n "$NS" get deploy --no-headers 2>/dev/null | grep -av memcache | awk '$2!="1/1"' | wc -l)
  RUN=$(sk -n "$NS" get pods --no-headers 2>/dev/null | grep -av memcache | grep -c Running)
  echo "  not-ready-deploys=$NR running-pods=$RUN"
  [ "${NR:-9}" -eq 0 ] && { echo "ALL READY"; break; }
  # keep rabbitmq probe generous
  sk -n "$NS" patch deploy rabbitmq --type=json -p '[{"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/timeoutSeconds","value":5}]' >/dev/null 2>&1
  sleep 20
done
echo "=== node placement (should be msp-at-big) ==="
sk -n "$NS" get pods -o wide 2>&1 | grep -av memcache | awk 'NR==1||/postgres|keycloak|clickhouse/{print $1, $7}' | head
echo "=== nudge shoot CR + wait Ready ==="
setup_kcp >/dev/null 2>&1; kcp_portforward >/dev/null 2>&1; trap 'pkill -f "port-forward.*root-proxy.*6443" 2>/dev/null||true' EXIT
sk -n "$NS" annotate aitrustplatforminstance my-aitrust nudge="$(date +%s)" --overwrite >/dev/null 2>&1
for i in $(seq 1 10); do
  P=$(kc "$WS" -n default get aitrustplatforminstance my-aitrust -o jsonpath='{.status.phase}/{.status.ready}' 2>/dev/null)
  echo "  status=$P"; [ "$P" = "Ready/true" ] && { echo READY; break; }; sleep 18
done
echo "=== external reachability ==="
URL=https://q3c0weh7suf5hgjk-my-aitrust.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu
sk -n platform-mesh-system run hit-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet -- \
  curl -sk -o /dev/null -w 'app http=%{http_code}\n' -H 'Host: q3c0weh7suf5hgjk-my-aitrust.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu' "$URL/" 2>&1 | grep -av memcache | grep http
