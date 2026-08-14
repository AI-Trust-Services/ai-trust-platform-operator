#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
NEWPW="$(head -c24 /dev/urandom | xxd -p)"   # 48-hex strong password
echo "=== patch app-secrets MINIO_ROOT_PASSWORD (rotated) ==="
B64=$(printf '%s' "$NEWPW" | base64 | tr -d '\n')
kubectl -n "$NS" patch secret app-secrets --type=json -p "[{\"op\":\"replace\",\"path\":\"/data/MINIO_ROOT_PASSWORD\",\"value\":\"$B64\"}]" 2>&1 | grep -avi memcache
echo "  rotated (len=${#NEWPW})"
echo "=== restart MinIO FIRST (server adopts new root creds), then its consumers ==="
kubectl -n "$NS" rollout restart deploy/minio 2>&1 | grep -avi memcache
kubectl -n "$NS" rollout status deploy/minio --timeout=120s 2>&1 | grep -avi memcache | tail -1
kubectl -n "$NS" rollout restart deploy/compliance-backend deploy/clickhouse 2>&1 | grep -avi memcache
kubectl -n "$NS" rollout status deploy/compliance-backend --timeout=150s 2>&1 | grep -avi memcache | tail -1
kubectl -n "$NS" rollout status deploy/clickhouse --timeout=150s 2>&1 | grep -avi memcache | tail -1
echo "=== compliance-backend pod status (should be Running now, guard satisfied) ==="
kubectl -n "$NS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep -E 'compliance-backend|minio|clickhouse' | awk '{printf "%-52s %-6s %s\n",$1,$2,$3}'
echo DONE
