#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
echo "=== delete hand-copied secret to prove the operator recreates it ==="
kubectl -n "$NS" delete secret mesh-keycloak-admin --ignore-not-found 2>&1 | grep -avi memcache
echo "=== set new env + restart operator (pull new v5) ==="
kubectl -n "$NS" set env deploy/aitrust-mt-operator MESH_KC_ADMIN_NS=platform-mesh-system MESH_KC_ADMIN_SECRET=keycloak-admin 2>&1 | grep -avi memcache
kubectl -n "$NS" rollout restart deploy/aitrust-mt-operator 2>&1 | grep -avi memcache
kubectl -n "$NS" rollout status deploy/aitrust-mt-operator --timeout=120s 2>&1 | grep -avi memcache | tail -1
echo "=== create a throwaway Subscription to trigger the copy, then delete it ==="
cat <<EOF | kubectl apply -f - 2>&1 | grep -avi memcache
apiVersion: sub.aitrustmt.msp/v1alpha1
kind: Subscription
metadata: { name: verify-copy, namespace: $NS }
spec: { org: poc2, adminEmail: "mircea.craciun@sap.com" }
EOF
sleep 12
echo "=== did the operator recreate mesh-keycloak-admin? ==="
kubectl -n "$NS" get secret mesh-keycloak-admin --no-headers 2>&1 | grep -avi memcache
echo "=== kc-client job result ==="
kubectl -n "$NS" get job kc-client-poc2 --no-headers 2>&1 | grep -avi memcache
kubectl -n "$NS" logs job/kc-client-poc2 --tail=4 2>&1 | grep -avi memcache | tail -4
echo "=== cleanup the verify sub + its resources ==="
kubectl -n "$NS" delete subscriptions.sub.aitrustmt.msp verify-copy --timeout=60s 2>&1 | grep -avi memcache
kubectl -n "$NS" delete job kc-client-poc2 --ignore-not-found 2>&1 | grep -avi memcache
kubectl -n "$NS" delete secret aitrust-mt-oauth2-poc2 --ignore-not-found 2>&1 | grep -avi memcache
kubectl -n "$NS" delete deploy,svc -l org=poc2 --ignore-not-found 2>&1 | grep -avi memcache
kubectl -n platform-mesh-system delete httproute aitrust-mt-poc2 --ignore-not-found 2>&1 | grep -avi memcache
kubectl -n "$NS" delete referencegrant allow-gw-to-oauth2-poc2 --ignore-not-found 2>&1 | grep -avi memcache
echo DONE
