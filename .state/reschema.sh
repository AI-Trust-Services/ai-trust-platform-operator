#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
setup_kcp; kcp_portforward
trap 'pkill -f "port-forward.*root-proxy.*6443" 2>/dev/null || true' EXIT

echo "=== 1. apply the updated CRD (no x-kubernetes-preserve-unknown-fields on status) ==="
sk apply -f charts/aitrust-msp-app/crds/aitrustplatforminstance.yaml 2>&1 | grep -av memcache

echo "=== 2. delete old APIResourceSchema + restart syncagent to republish ==="
for s in $(kc "$PROVIDER_WS" get apiresourceschema -o name 2>/dev/null | grep aitrust); do
  kc "$PROVIDER_WS" delete "$s" 2>&1 | grep -av memcache
done
sk -n "$PROVIDER_NS" rollout restart deploy/aitrust-syncagent 2>&1 | grep -av memcache
sk -n "$PROVIDER_NS" rollout status deploy/aitrust-syncagent --timeout=120s 2>&1 | grep -av memcache | tail -1

echo "=== 3. wait for new schema + APIExport to republish ==="
for i in $(seq 1 20); do
  N=$(kc "$PROVIDER_WS" get apiresourceschema -o name 2>/dev/null | grep -c aitrust)
  R=$(kc "$PROVIDER_WS" get apiexport "$EXPORT_NAME" -o jsonpath='{range .spec.resources[*]}{.name}{"\n"}{end}' 2>/dev/null | grep -c aitrustplatforminstances)
  echo "  schemas=$N exportResources=$R"
  [ "${N:-0}" -ge 1 ] && [ "${R:-0}" -ge 1 ] && { echo "republished"; break; }
  sleep 8
done
kc "$PROVIDER_WS" get apiresourceschema 2>&1 | grep -av memcache | grep aitrust
echo "=== 4. confirm status subtree no longer has preserve-unknown ==="
SCH=$(kc "$PROVIDER_WS" get apiresourceschema -o name 2>/dev/null | grep aitrust | head -1)
kc "$PROVIDER_WS" get "$SCH" -o jsonpath='{.spec.versions[0].schema.properties.status.x-kubernetes-preserve-unknown-fields}{"\n"}' 2>&1 | grep -av memcache
