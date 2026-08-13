#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
echo "=== token via Service DNS from a curl pod (admin exists now — expect 200) ==="
kubectl -n "$NS" run t-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet --command -- \
  sh -c 'curl -s -o /dev/null -w "svc-dns token: http=%{http_code}\n" -d "client_id=admin-cli&username=admin&password=admin&grant_type=password" http://keycloak.aitrust-mt-msp.svc.cluster.local:8080/keycloak/realms/master/protocol/openid-connect/token' 2>&1 | grep -avi memcache | grep http=

echo "=== nudge the operator to recreate the tenant-provision job (bounce it) ==="
kubectl -n "$NS" rollout restart deploy/aitrust-mt-operator 2>&1 | grep -avi memcache
sleep 45
echo "=== tenant-provision job + pod status now (operator v2, fixed secret refs) ==="
kubectl -n "$NS" get jobs 2>&1 | grep -avi memcache | grep -E 'prov-|keycloak-provision|NAME'
kubectl -n "$NS" get pods 2>&1 | grep -avi memcache | grep -E 'prov-|keycloak-provision'
echo "=== if a prov pod exists, its logs ==="
PP=$(kubectl -n "$NS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep 'prov-' | awk '{print $1}' | head -1)
[ -n "$PP" ] && kubectl -n "$NS" logs "$PP" --tail=15 2>&1 | grep -avi memcache | tail -15
echo "=== Subscription status ==="
kubectl get subscriptions.sub.aitrustmt.msp -A -o jsonpath='{range .items[*]}{.metadata.name}{" ready="}{.status.ready}{" phase="}{.status.phase}{"\n"}{end}' 2>&1 | grep -avi memcache
echo DONE
