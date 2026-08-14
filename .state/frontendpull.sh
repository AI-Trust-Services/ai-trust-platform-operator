#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
echo "=== alerts-frontend imagePullPolicy + image ==="
kubectl -n "$NS" get deploy alerts-frontend -o jsonpath='image={.spec.template.spec.containers[0].image} pull={.spec.template.spec.containers[0].imagePullPolicy}{"\n"}' 2>&1 | grep -avi memcache
echo "=== pods for alerts-frontend (age) ==="
kubectl -n "$NS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep alerts-frontend
echo "=== force Always pull on all 7 frontends + restart ==="
for d in ai-system-registry-frontend monitoring-frontend overview-frontend alerts-frontend compliance-frontend decision-trace-analyzer-frontend users-frontend; do
  kubectl -n "$NS" patch deploy "$d" --type=json -p '[{"op":"replace","path":"/spec/template/spec/containers/0/imagePullPolicy","value":"Always"}]' >/dev/null 2>&1
  kubectl -n "$NS" rollout restart deploy/"$d" >/dev/null 2>&1
done
for d in alerts-frontend overview-frontend compliance-frontend; do
  kubectl -n "$NS" rollout status deploy/"$d" --timeout=120s 2>&1 | grep -avi memcache | tail -1
done
echo "=== re-check served headers from a FRESH alerts-frontend pod ==="
sleep 3
kubectl -n "$NS" run fh-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet --command -- \
  sh -c 'curl -s -D - -o /dev/null http://alerts-frontend:80/ | grep -iE "x-frame-options|frame-ancestors|access-control-allow-origin"' 2>&1 | grep -avi memcache | head
echo "(expect: X-Frame-Options SAMEORIGIN, frame-ancestors self, NO Access-Control-Allow-Origin)"
echo DONE
