#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
GWNS=platform-mesh-system; APPNS=aitrust-mt-msp
echo "=== A) mesh openfga svc + ports ==="
kubectl -n "$GWNS" get svc openfga -o jsonpath='{range .spec.ports[*]}{.name}={.port} {end}{"\n"}' 2>&1 | grep -avi memcache
echo "=== B) is there an Istio AuthorizationPolicy gating openfga? (cross-ns access blocked?) ==="
kubectl -n "$GWNS" get authorizationpolicy 2>&1 | grep -avi memcache | grep -iE 'openfga|NAME' | head
echo "=== C) can a pod IN the app namespace reach mesh openfga:8080? (the real test) ==="
kubectl -n "$APPNS" run fgareach-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet --command -- \
  sh -c "curl -s -o /dev/null -w 'app-ns -> mesh openfga /healthz: http=%{http_code}\n' -m 8 http://openfga.$GWNS.svc.cluster.local:8080/healthz" 2>&1 | grep -avi memcache | grep -E 'http=|command'
kubectl -n "$APPNS" run fgareach2-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet --command -- \
  sh -c "curl -s -o /dev/null -w 'app-ns -> mesh openfga /stores: http=%{http_code}\n' -m 8 http://openfga.$GWNS.svc.cluster.local:8080/stores" 2>&1 | grep -avi memcache | grep -E 'http='
echo "=== D) mesh openfga image version (model/api compat with app's openfga-sdk) ==="
kubectl -n "$GWNS" get deploy openfga -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}' 2>&1 | grep -avi memcache
echo DONE
