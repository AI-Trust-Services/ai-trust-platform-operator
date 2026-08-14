#!/bin/bash
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
f(){ grep -avi memcache; }
echo "=== operator deploy image + pod + startup version log ==="
kubectl -n "$NS" get deploy aitrust-mt-operator -o jsonpath='image={.spec.template.spec.containers[0].image} pullPolicy={.spec.template.spec.containers[0].imagePullPolicy}{"\n"}' 2>&1 | f
kubectl -n "$NS" get pods -l app=aitrust-mt-operator --no-headers 2>&1 | f
kubectl -n "$NS" logs deploy/aitrust-mt-operator --tail=20 2>&1 | f | grep -iE 'v1[0-9] starting' | tail -1
echo; echo "=== does the LOCAL v15 image contain the new template text 'provisioned role'? ==="
docker run --rm --entrypoint sh "$OPERATOR_IMAGE:$OPERATOR_TAG" -c 'grep -c "provisioned role" /manifests/tenant-stores-job.tmpl 2>/dev/null || echo "0 (or path differs)"' 2>&1 | tail -3 || echo "  (cannot introspect image)"
