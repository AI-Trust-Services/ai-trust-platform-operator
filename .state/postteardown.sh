#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
echo "=== operator recreating mesh-keycloak-admin + re-reconciling? ==="
sleep 15
kubectl -n "$NS" get secret mesh-keycloak-admin --no-headers 2>&1 | grep -avi memcache || echo "  mesh-keycloak-admin NOT recreated yet"
echo "=== operator logs (recent) ==="
kubectl -n "$NS" logs deploy/aitrust-mt-operator --tail=15 2>&1 | grep -avi memcache | grep -iE 'reconcile|Ready|Degraded|error|org|secret' | tail -8
echo "=== subscriptions phase now ==="
kubectl get subscriptions.sub.aitrustmt.msp -A -o jsonpath='{range .items[*]}{.metadata.name} org={.spec.org} phase={.status.phase}{"\n"}{end}' 2>&1 | grep -avi memcache
echo "=== shared app + operator pods ==="
kubectl -n "$NS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep -E 'operator|shell' | awk '{printf "%-50s %-6s %s\n",$1,$2,$3}'
echo DONE
