#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
echo "=== app-secrets keys (plain list) ==="
kubectl -n "$NS" get secret app-secrets -o go-template='{{range $k,$v := .data}}{{$k}}{{"\n"}}{{end}}' 2>&1 | grep -avi memcache
echo "=== keycloak admin creds (decoded) ==="
kubectl -n "$NS" get secret app-secrets -o jsonpath='{.data.KEYCLOAK_ADMIN}' 2>/dev/null | base64 -d; echo " <- KEYCLOAK_ADMIN"
kubectl -n "$NS" get secret app-secrets -o jsonpath='{.data.KEYCLOAK_ADMIN_PASSWORD}' 2>/dev/null | base64 -d; echo " <- KEYCLOAK_ADMIN_PASSWORD"
echo "=== keycloak deployment env (what admin env the KC container actually uses) ==="
kubectl -n "$NS" get deploy keycloak -o jsonpath='{range .spec.template.spec.containers[0].env[*]}{.name}={.value}{"  (from "}{.valueFrom.secretKeyRef.key}{")"}{"\n"}{end}' 2>&1 | grep -avi memcache | grep -iE 'ADMIN|KC_|BOOTSTRAP|RELATIVE'
echo "=== keycloak container args/command (relative path?) ==="
kubectl -n "$NS" get deploy keycloak -o jsonpath='{.spec.template.spec.containers[0].args}{"\n"}{.spec.template.spec.containers[0].command}{"\n"}' 2>&1 | grep -avi memcache
echo "=== what URL does provision.py hit? (KEYCLOAK_URL env of the crashing job) ==="
kubectl -n "$NS" get job keycloak-provision -o jsonpath='{range .spec.template.spec.containers[0].env[*]}{.name}={.value}{"\n"}{end}' 2>&1 | grep -avi memcache | grep -iE 'KEYCLOAK_URL|ADMIN'
