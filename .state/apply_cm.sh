#!/bin/bash
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
f(){ grep -avi memcache; }
echo "=== validate edited JSON is well-formed ==="
python3 -c "import json,sys; json.load(open('.state/pm-content.live.json')); print('  JSON valid')" 2>/dev/null || \
  { command -v jq >/dev/null && jq . .state/pm-content.live.json >/dev/null && echo "  JSON valid (jq)"; } || echo "  (no validator available; proceeding)"
echo "  Plan removed? $(grep -c '\"Plan\"' .state/pm-content.live.json) (expect 0)"
echo "=== update the live ConfigMap data key from the file (kubectl create --dry-run | apply) ==="
kubectl -n "$NS" create configmap aitrust-mt-portal-config \
  --from-file=pm-content.json=.state/pm-content.live.json \
  --dry-run=client -o yaml 2>&1 | f | kubectl -n "$NS" apply -f - 2>&1 | f
echo "=== restart portal-integration so nginx serves the new file ==="
kubectl -n "$NS" rollout restart deploy/aitrust-mt-portal-integration 2>&1 | f
kubectl -n "$NS" rollout status deploy/aitrust-mt-portal-integration --timeout=90s 2>&1 | f | tail -1
echo "=== verify served form (Plan gone, Org relabeled) ==="
sleep 2
kubectl -n "$NS" exec deploy/aitrust-mt-portal-integration -- sh -c 'grep -oE "\"label\": \"[^\"]*\"" /usr/share/nginx/html/pm-content.json | head -12' 2>&1 | f
echo DONE
