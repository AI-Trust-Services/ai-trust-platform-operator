#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
echo "=== 1. all pods healthy ==="
bad=$(kubectl -n "$NS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep -vE 'Running|Completed' | wc -l)
echo "  non-healthy pods: $bad"
echo "=== 2. SEC-M1: FORCE RLS on all 11 tables ==="
PGPOD=$(kubectl -n "$NS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep -E '^postgres' | awk '{print $1}' | head -1)
kubectl -n "$NS" exec "$PGPOD" -- sh -lc "PGPASSWORD=\$POSTGRES_PASSWORD psql -U \$POSTGRES_USER -d ai_trust -tA -c \"SELECT count(*) AS forced FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relforcerowsecurity\"" 2>&1 | grep -avi memcache | head -1
echo "  (expect 11)"
echo "=== 3. SEC-C3-CH: alerts-backend has tenant-scoped UPDATEs (grep running image) ==="
kubectl -n "$NS" exec deploy/alerts-backend -- sh -lc 'grep -c "tenant_clause" /app/app/routers/alerts.py' 2>&1 | grep -avi memcache | head -1
echo "  (expect >=6: 3 reads + 3 UPDATE mutations)"
echo "=== 4. SEC-H: all 7 frontends serve SAMEORIGIN, none ALLOWALL ==="
for fe in ai-system-registry monitoring overview alerts compliance decision-trace-analyzer users; do
  h=$(kubectl -n "$NS" run c-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet --command -- \
    sh -c "curl -s -D - -o /dev/null http://${fe}-frontend:80/ | grep -i x-frame-options | tr -d '\r'" 2>&1 | grep -avi memcache | grep -i x-frame | head -1)
  echo "  $fe-frontend: ${h:-<none>}"
done
echo DONE
