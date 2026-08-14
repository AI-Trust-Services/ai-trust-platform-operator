#!/bin/bash
# Post-build deploy: apply migrations 0010 (pg) + 0003 (clickhouse), set jwt-verify env,
# roll backends+worker+shell+consumer to the new images.
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config
rm -f "$SHOOT_KUBECONFIG"; mint_shoot_kubeconfig
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
PGPOD=$(kubectl -n "$NS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep -E '^postgres' | awk '{print $1}' | head -1)

echo "=== 1. pg migration 0010 (RLS write-own) via db-migrate image ==="
kubectl -n "$NS" delete job db-migrate-0010 --ignore-not-found 2>&1 | grep -avi memcache
cat <<EOF | kubectl -n "$NS" apply -f - 2>&1 | grep -avi memcache
apiVersion: batch/v1
kind: Job
metadata: { name: db-migrate-0010, namespace: $NS }
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
kubectl -n "$NS" wait --for=condition=complete job/db-migrate-0010 --timeout=180s 2>&1 | grep -avi memcache || true
kubectl -n "$NS" logs job/db-migrate-0010 2>&1 | grep -avi memcache | grep -iE 'upgrade|0010|error' | tail -5

echo "=== 2. clickhouse migration 0003 (tenant_id) ==="
CHPOD=$(kubectl -n "$NS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep -E '^clickhouse-[0-9a-f]' | awk '{print $1}' | head -1)
echo "ch pod: $CHPOD"
kubectl -n "$NS" exec "$CHPOD" -- clickhouse-client -q "ALTER TABLE otel.gen_ai_spans ADD COLUMN IF NOT EXISTS tenant_id String DEFAULT ''" 2>&1 | grep -avi memcache
kubectl -n "$NS" exec "$CHPOD" -- clickhouse-client -q "ALTER TABLE otel.alert_events ADD COLUMN IF NOT EXISTS tenant_id String DEFAULT ''" 2>&1 | grep -avi memcache
kubectl -n "$NS" exec "$CHPOD" -- clickhouse-client -q "SELECT 'gen_ai_spans has tenant_id: '||toString(count()) FROM system.columns WHERE database='otel' AND table='gen_ai_spans' AND name='tenant_id'" 2>&1 | grep -avi memcache

echo "=== 3. set jwt-verify env on all backends (JWKS issuer base = mesh public keycloak) ==="
SUFFIX="ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu"
ISSBASE="https://$SUFFIX/keycloak/realms"
for d in ai-system-registry-backend monitoring-backend overview-backend alerts-backend compliance-backend decision-trace-analyzer-backend users-backend policy-checker-worker; do
  kubectl -n "$NS" set env deploy/$d TENANCY_JWKS_ISSUER_BASE="$ISSBASE" >/dev/null 2>&1 && echo "  env set $d"
done

echo "=== 4. roll to new images ==="
for d in ai-system-registry-backend monitoring-backend overview-backend alerts-backend compliance-backend decision-trace-analyzer-backend users-backend policy-checker-worker otel-clickhouse-consumer shell; do
  kubectl -n "$NS" rollout restart deploy/$d >/dev/null 2>&1
done
for d in ai-system-registry-backend alerts-backend compliance-backend decision-trace-analyzer-backend monitoring-backend users-backend shell; do
  kubectl -n "$NS" rollout status deploy/$d --timeout=150s 2>&1 | grep -avi memcache | tail -1
done
echo DONE
