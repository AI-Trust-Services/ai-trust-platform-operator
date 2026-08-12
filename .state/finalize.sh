#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
NS=aitp-q3c0weh7suf5hgjk-my-aitrust
WS="root:orgs:$ORG_NAME:$ACCOUNT_NAME"
sk -n "$NS" patch deploy rabbitmq --type=json -p '[{"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/timeoutSeconds","value":5},{"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/periodSeconds","value":15}]' >/dev/null 2>&1
sk -n "$NS" rollout status deploy/rabbitmq --timeout=120s 2>&1 | grep -av memcache | tail -1
setup_kcp >/dev/null 2>&1; kcp_portforward >/dev/null 2>&1; trap 'pkill -f "port-forward.*root-proxy.*6443" 2>/dev/null||true' EXIT
sk -n "$NS" annotate aitrustplatforminstance my-aitrust nudge="$(date +%s)" --overwrite >/dev/null 2>&1 || \
  sk get aitrustplatforminstance -A -o name 2>/dev/null | head -1 | xargs -I{} sk -n "$NS" annotate {} nudge=x --overwrite >/dev/null 2>&1
for i in $(seq 1 10); do
  P=$(kc "$WS" -n default get aitrustplatforminstance my-aitrust -o jsonpath='{.status.phase}/{.status.ready}' 2>/dev/null)
  echo "  status=$P"; [ "$P" = "Ready/true" ] && { echo READY; break; }; sleep 18
done
echo "=== external reachability (expect 302->keycloak or 200) ==="
URL=https://q3c0weh7suf5hgjk-my-aitrust.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu
sk -n platform-mesh-system run hit-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet -- \
  curl -sk -o /dev/null -w 'app http=%{http_code}\n' "$URL/" 2>&1 | grep -av memcache | grep http
