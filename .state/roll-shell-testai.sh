#!/bin/bash
# Roll the fixed shell for the ONE reported instance (testai) only, then verify served viewUrls are relative.
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
rm -f "$SHOOT_KUBECONFIG"; mint_shoot_kubeconfig >/dev/null 2>&1 || { echo LOGIN_EXPIRED; exit 3; }
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitp-33hins0iklcwfg45-testai
echo "=== patch shell imagePullPolicy->Always + restart ($NS) ==="
kubectl -n "$NS" patch deploy shell --type=json \
  -p '[{"op":"replace","path":"/spec/template/spec/containers/0/imagePullPolicy","value":"Always"}]' 2>&1 | grep -av memcache
kubectl -n "$NS" rollout restart deploy/shell 2>&1 | grep -av memcache
kubectl -n "$NS" rollout status  deploy/shell --timeout=150s 2>&1 | grep -av memcache | tail -1
echo "=== VERIFY served viewUrls are RELATIVE (expect /overview/ etc., NO http://, NO ai-trust-platform-main) ==="
kubectl -n "$NS" exec deploy/shell -- cat /usr/share/nginx/html/luigi-config.js 2>/dev/null \
  | grep -av memcache | grep -E 'viewUrl'
