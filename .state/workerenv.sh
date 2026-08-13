#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
echo "=== policy-checker-worker env (DB urls available?) ==="
kubectl -n "$NS" get deploy policy-checker-worker -o jsonpath='{range .spec.template.spec.containers[0].env[*]}{.name}={.value}{"\n"}{end}' 2>&1 | grep -avi memcache | grep -iE 'DATABASE|OWNER|APP_DB|POSTGRES|TENANCY'
echo "=== secret app-secrets keys (which DB urls exist) ==="
kubectl -n "$NS" get secret app-secrets -o jsonpath='{range .data}{@}{end}' 2>&1 | grep -avi memcache >/dev/null
kubectl -n "$NS" get secret app-secrets -o go-template='{{range $k,$v := .data}}{{$k}}{{"\n"}}{{end}}' 2>&1 | grep -avi memcache | grep -iE 'DATABASE|DB'
echo DONE
