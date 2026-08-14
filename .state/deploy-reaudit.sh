#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config
rm -f "$SHOOT_KUBECONFIG"; mint_shoot_kubeconfig 2>&1 | grep -avi memcache | tail -1
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
echo "=== 1. migration 0011 (FORCE RLS) via db-migrate job ==="
kubectl -n "$NS" delete job db-migrate-0011 --ignore-not-found 2>&1 | grep -avi memcache
cat <<EOF | kubectl -n "$NS" apply -f - 2>&1 | grep -avi memcache
apiVersion: batch/v1
kind: Job
metadata: { name: db-migrate-0011, namespace: $NS }
spec:
  backoffLimit: 1
  template:
    spec:
      restartPolicy: Never
      nodeSelector: { workload: ai-trust-mt }
      tolerations: [{ key: workload, operator: Equal, value: ai-trust-mt, effect: NoSchedule }]
      containers:
      - name: db-migrate
        image: $REGISTRY/aitrust-db-migrate:$TAG
        imagePullPolicy: Always
        env:
        - { name: DATABASE_URL, valueFrom: { secretKeyRef: { name: app-secrets, key: DATABASE_URL } } }
EOF
kubectl -n "$NS" wait --for=condition=complete job/db-migrate-0011 --timeout=180s 2>&1 | grep -avi memcache || true
kubectl -n "$NS" logs job/db-migrate-0011 2>&1 | grep -avi memcache | grep -iE 'upgrade|0011|force|error' | tail -4

echo "=== 2. verify FORCE RLS on ai_systems ==="
PGPOD=$(kubectl -n "$NS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep -E '^postgres' | awk '{print $1}' | head -1)
kubectl -n "$NS" exec "$PGPOD" -- sh -lc "PGPASSWORD=\$POSTGRES_PASSWORD psql -U \$POSTGRES_USER -d ai_trust -tA -c \"SELECT relname||' force='||relforcerowsecurity FROM pg_class WHERE relname IN ('ai_systems','alert_rules') ORDER BY 1\"" 2>&1 | grep -avi memcache | head

echo "=== 3. roll alerts backend + worker + 7 frontends + shell to new images ==="
for d in alerts-backend policy-checker-worker shell ai-system-registry-frontend monitoring-frontend overview-frontend alerts-frontend compliance-frontend decision-trace-analyzer-frontend users-frontend; do
  kubectl -n "$NS" rollout restart deploy/$d >/dev/null 2>&1
done
for d in alerts-backend shell alerts-frontend; do
  kubectl -n "$NS" rollout status deploy/$d --timeout=150s 2>&1 | grep -avi memcache | tail -1
done
echo "=== 4. verify a frontend no longer serves ALLOWALL/wildcard (curl the frontend svc) ==="
kubectl -n "$NS" run fh-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet --command -- \
  sh -c 'curl -s -D - -o /dev/null http://alerts-frontend:80/ | grep -iE "x-frame-options|frame-ancestors|access-control-allow-origin"' 2>&1 | grep -avi memcache | head
echo DONE
