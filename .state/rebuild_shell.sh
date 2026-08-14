#!/bin/bash
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
SRC="$BUNDLE/../ai-trust-platform-git"
echo "=== rebuild shell (no-cache for luigi-config.js) ==="
cd "$SRC"
docker build -q -t aitrust/shell:build ./shell >/dev/null && echo "  built"
docker tag aitrust/shell:build "$REGISTRY/aitrust-shell:$TAG"
docker push -q "$REGISTRY/aitrust-shell:$TAG" && echo "  pushed"
cd "$BUNDLE"
kubectl -n aitrust-mt-msp rollout restart deploy/shell 2>&1 | grep -avi memcache
kubectl -n aitrust-mt-msp rollout status deploy/shell --timeout=120s 2>&1 | grep -avi memcache | tail -1
echo "=== verify served header ==="
kubectl -n aitrust-mt-msp run shdrcheck-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet --command -- \
  sh -c 'curl -s -D - -o /dev/null http://shell.aitrust-mt-msp.svc.cluster.local:80/luigi-config.js | grep -i "cache-control\|HTTP/"' 2>&1 | grep -avi memcache
echo DONE
