#!/bin/bash
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
f(){ grep -avi memcache; }
CHPOD=$(kubectl -n "$NS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep -E '^clickhouse' | awk '{print $1}' | head -1)
echo "=== ClickHouse databases (expect otel + tenant_<org> per tenant) ==="
kubectl -n "$NS" exec "$CHPOD" -- clickhouse-client -q "SHOW DATABASES" 2>&1 | f | grep -iE 'otel|tenant_' || true
echo "=== tables inside tenant_mirceatest (expect gen_ai_spans, alert_events, schema_migrations) ==="
kubectl -n "$NS" exec "$CHPOD" -- clickhouse-client -q "SHOW TABLES FROM tenant_mirceatest" 2>&1 | f
echo
echo "=== MinIO buckets (expect evidence-files + tenant-<org> per tenant) ==="
MU=$(kubectl -n "$NS" get secret app-secrets -o jsonpath='{.data.MINIO_ROOT_USER}' | base64 -d)
MP=$(kubectl -n "$NS" get secret app-secrets -o jsonpath='{.data.MINIO_ROOT_PASSWORD}' | base64 -d)
kubectl -n "$NS" run mcls-$RANDOM --rm -i --restart=Never --image=minio/mc:RELEASE.2025-08-13T08-35-41Z --quiet \
  --env="MU=$MU" --env="MP=$MP" --command -- sh -c 'mc alias set l http://minio.aitrust-mt-msp.svc.cluster.local:9000 "$MU" "$MP" >/dev/null && mc ls l' 2>&1 | f | grep -iE 'tenant-|evidence' || true
echo
echo "=== subscription phases (real orgs Ready) ==="
kubectl get subscriptions.sub.aitrustmt.msp -A -o jsonpath='{range .items[*]}{.spec.org}={.status.phase}{"\n"}{end}' 2>&1 | f | grep -vE '^=' | sort -u
echo "=== backends healthy? ==="
kubectl -n "$NS" get pods --no-headers 2>&1 | f | grep -ivE '1/1|Completed' | grep -iE 'backend|consumer|compliance' || echo "  (all backends 1/1)"
echo DONE
