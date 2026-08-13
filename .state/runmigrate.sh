#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
IMG="$REGISTRY/aitrust-db-migrate:$TAG"
echo "=== run db-migrate job (alembic upgrade head) with OWNER DATABASE_URL ==="
# owner DATABASE_URL from the secret (postgres role) — migrations must run as owner.
kubectl -n "$NS" delete job db-migrate-0009 --ignore-not-found 2>&1 | grep -avi memcache
cat <<EOF | kubectl -n "$NS" apply -f - 2>&1 | grep -avi memcache
apiVersion: batch/v1
kind: Job
metadata: { name: db-migrate-0009, namespace: $NS }
spec:
  backoffLimit: 1
  template:
    spec:
      restartPolicy: Never
      nodeSelector: { "workload": "ai-trust-mt" }
      tolerations:
      - { key: "workload", operator: "Equal", value: "ai-trust-mt", effect: "NoSchedule" }
      containers:
      - name: db-migrate
        image: $IMG
        imagePullPolicy: Always
        env:
        - { name: DATABASE_URL, valueFrom: { secretKeyRef: { name: app-secrets, key: DATABASE_URL } } }
EOF
echo "--- wait for completion ---"
kubectl -n "$NS" wait --for=condition=complete job/db-migrate-0009 --timeout=180s 2>&1 | grep -avi memcache || \
  kubectl -n "$NS" wait --for=condition=failed job/db-migrate-0009 --timeout=10s 2>&1 | grep -avi memcache
echo "--- logs ---"
kubectl -n "$NS" logs job/db-migrate-0009 --tail=30 2>&1 | grep -avi memcache | tail -30
echo DONE
