#!/bin/bash
exec > /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP/.state/pullpolicy.out 2>&1
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
kubectl get ns >/dev/null 2>&1 || { echo LOGIN_EXPIRED; exit 3; }

# app deployments whose containers use our aitrust images (skip infra: postgres/clickhouse/minio/rabbitmq/keycloak/otel-collector = 3rd-party or heavy stateful; leave IfNotPresent)
APP_DEPLOYS="ai-system-registry-backend monitoring-backend overview-backend alerts-backend compliance-backend decision-trace-analyzer-backend ai-system-registry-frontend monitoring-frontend overview-frontend alerts-frontend compliance-frontend decision-trace-analyzer-frontend policy-checker-worker otel-clickhouse-consumer otel-rmq-bridge shell oauth2-proxy"

for NS in $(kubectl get ns -o name 2>/dev/null | grep -avi memcache | grep -oE 'aitp-[a-z0-9-]+'); do
  echo "==== $NS ===="
  changed=0
  for d in $APP_DEPLOYS; do
    kubectl -n "$NS" get deploy "$d" >/dev/null 2>&1 || continue
    cur=$(kubectl -n "$NS" get deploy "$d" -o jsonpath='{.spec.template.spec.containers[0].imagePullPolicy}' 2>/dev/null)
    if [ "$cur" != "Always" ]; then
      cname=$(kubectl -n "$NS" get deploy "$d" -o jsonpath='{.spec.template.spec.containers[0].name}' 2>/dev/null)
      kubectl -n "$NS" patch deploy "$d" --type=json \
        -p "[{\"op\":\"replace\",\"path\":\"/spec/template/spec/containers/0/imagePullPolicy\",\"value\":\"Always\"}]" >/dev/null 2>&1 && changed=$((changed+1))
    fi
  done
  echo "  patched-to-Always: $changed deployments"
done

echo
echo "==== wait ~40s for rollouts, then confirm each instance healthy (no crashloops) ===="
sleep 40
for NS in $(kubectl get ns -o name 2>/dev/null | grep -avi memcache | grep -oE 'aitp-[a-z0-9-]+'); do
  bad=$(kubectl -n "$NS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep -vE 'Running|Completed' | wc -l)
  running=$(kubectl -n "$NS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep -c Running)
  echo "  $NS: running=$running not-ready=$bad"
  [ "$bad" -gt 0 ] && kubectl -n "$NS" get pods --no-headers 2>&1 | grep -avi memcache | grep -vE 'Running|Completed' | sed 's/^/     /' | head
done

echo
echo "==== sample: confirm Always is set on a few app deploys ===="
NS=aitp-wzw3g7znvmqdk5qf-pocaitrust
for d in overview-backend shell oauth2-proxy policy-checker-worker; do
  echo -n "  $NS/$d: "; kubectl -n "$NS" get deploy "$d" -o jsonpath='{.spec.template.spec.containers[0].imagePullPolicy}{"\n"}' 2>&1 | grep -avi memcache
done
echo DONE
