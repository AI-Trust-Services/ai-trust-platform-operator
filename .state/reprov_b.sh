#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
IMG="$REGISTRY/aitrust-db-migrate:$TAG"
echo "=== run db-migrate (alembic 0001->head) on the fresh DB ==="
kubectl -n "$NS" delete job db-migrate-clean --ignore-not-found 2>&1 | grep -avi memcache
cat <<EOF | kubectl -n "$NS" apply -f - 2>&1 | grep -avi memcache
apiVersion: batch/v1
kind: Job
metadata: { name: db-migrate-clean, namespace: $NS }
spec:
  backoffLimit: 1
  template:
    spec:
      restartPolicy: Never
      nodeSelector: { workload: ai-trust-mt }
      tolerations: [{ key: workload, operator: Equal, value: ai-trust-mt, effect: NoSchedule }]
      containers:
      - name: db-migrate
        image: $IMG
        imagePullPolicy: Always
        env:
        - { name: DATABASE_URL, valueFrom: { secretKeyRef: { name: app-secrets, key: DATABASE_URL } } }
EOF
kubectl -n "$NS" wait --for=condition=complete job/db-migrate-clean --timeout=240s 2>&1 | grep -avi memcache || \
  kubectl -n "$NS" wait --for=condition=failed job/db-migrate-clean --timeout=5s 2>&1 | grep -avi memcache
echo "--- migrate logs ---"
kubectl -n "$NS" logs job/db-migrate-clean 2>&1 | grep -avi memcache | grep -iE 'running upgrade|error|INSERT|complete' | tail -20
echo DONE
