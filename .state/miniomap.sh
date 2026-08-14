#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
echo "=== who consumes MINIO_ROOT_PASSWORD (deployments referencing it) ==="
for d in $(kubectl -n "$NS" get deploy -o name 2>/dev/null | grep -avi memcache); do
  n=$(basename "$d")
  hit=$(kubectl -n "$NS" get "$d" -o jsonpath='{range .spec.template.spec.containers[0].env[?(@.name=="MINIO_ROOT_PASSWORD")]}FROM={.valueFrom.secretKeyRef.name}/{.valueFrom.secretKeyRef.key} VAL={.value}{end}' 2>/dev/null | grep -avi memcache)
  [ -n "$hit" ] && echo "  $n -> $hit"
done
echo "=== minio server: how does it get the password? ==="
kubectl -n "$NS" get deploy minio -o jsonpath='{range .spec.template.spec.containers[0].env[*]}{.name}{" <- "}{.valueFrom.secretKeyRef.name}/{.valueFrom.secretKeyRef.key}{"\n"}{end}' 2>&1 | grep -avi memcache | grep -iE 'MINIO_ROOT|MINIO_SECRET'
echo "=== clickhouse cold-tier: does it reference the minio password? (storage.xml / env) ==="
kubectl -n "$NS" get deploy clickhouse -o jsonpath='{range .spec.template.spec.containers[0].env[*]}{.name}={.value}{"\n"}{end}' 2>&1 | grep -avi memcache | grep -iE 'MINIO|S3|secret' | head
echo "=== app-secrets keys present ==="
kubectl -n "$NS" get secret app-secrets -o go-template='{{range $k,$v := .data}}{{$k}}{{"\n"}}{{end}}' 2>&1 | grep -avi memcache | grep -iE 'MINIO'
echo "=== is minio storing data on a PVC (password baked at first-boot) or ephemeral? ==="
kubectl -n "$NS" get deploy minio -o jsonpath='{.spec.template.spec.volumes}{"\n"}' 2>&1 | grep -avi memcache | tr ',' '\n' | grep -iE 'persistentVolumeClaim|emptyDir|claimName' | head
echo DONE
