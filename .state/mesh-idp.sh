#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
GWNS=platform-mesh-system
echo "=== A) mesh Keycloak: one shared instance? realms present (per-account)? ==="
kubectl -n "$GWNS" get deploy 2>&1 | grep -avi memcache | grep -iE 'keycloak|iam' | head
echo "-- realms in the mesh keycloak (list via kcadm on the mesh KC pod) --"
KCPOD=$(kubectl -n "$GWNS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep -iE 'keycloak-[0-9a-f]' | awk '{print $1}' | head -1)
echo "mesh kc pod: $KCPOD"
[ -n "$KCPOD" ] && kubectl -n "$GWNS" exec "$KCPOD" -- sh -lc '/opt/keycloak/bin/kcadm.sh config credentials --server http://localhost:8080/keycloak --realm master --user "$KEYCLOAK_ADMIN" --password "$KEYCLOAK_ADMIN_PASSWORD" >/dev/null 2>&1 && /opt/keycloak/bin/kcadm.sh get realms --fields realm 2>/dev/null' 2>&1 | grep -avi memcache | grep realm | head -20
echo
echo "=== B) mesh OpenFGA: one shared instance? per-account Stores? ==="
kubectl -n "$GWNS" get deploy 2>&1 | grep -avi memcache | grep -iE 'openfga|fga' | head
echo "-- Store CRs per account (core.platform-mesh.io) --"
kubectl get stores.core.platform-mesh.io -A 2>&1 | grep -avi memcache | head -20 || kubectl get stores -A 2>&1 | grep -avi memcache | head
echo
echo "=== C) how the mesh maps account -> realm + store (the account-operator / iam wiring) ==="
kubectl -n "$GWNS" get cm,secret 2>&1 | grep -avi memcache | grep -iE 'iam|realm|store' | head
echo DONE
