#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
echo "=== WHY the tenant-provision pod is CreateContainerConfigError (describe events) ==="
POD=$(kubectl -n "$NS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep 'prov-' | awk '{print $1}' | head -1)
echo "pod=$POD"
kubectl -n "$NS" describe pod "$POD" 2>&1 | grep -avi memcache | grep -iE 'Error|not found|secret|key|Warning|Reason' | head -15
echo
echo "=== what secrets exist + their keys ==="
kubectl -n "$NS" get secret 2>&1 | grep -avi memcache | grep -iE 'keycloak|app-secrets|NAME'
echo "-- app-secrets keys --"
kubectl -n "$NS" get secret app-secrets -o jsonpath='{range $k,$v := .data}{$k}{"\n"}{end}' 2>&1 | grep -avi memcache
echo "-- is there a keycloak-admin secret? --"
kubectl -n "$NS" get secret keycloak-admin 2>&1 | grep -avi memcache || echo "  (no keycloak-admin secret — THIS is the job's missing ref)"
echo
echo "=== WHY the shared app's own keycloak-provision crashloops ==="
KP=$(kubectl -n "$NS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep 'keycloak-provision' | awk '{print $1}' | head -1)
kubectl -n "$NS" logs "$KP" --tail=20 2>&1 | grep -avi memcache | tail -20
