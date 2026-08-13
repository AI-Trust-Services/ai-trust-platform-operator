#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
GWNS=platform-mesh-system
KCPOD=$(kubectl -n "$GWNS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep -E '^keycloak-[0-9a-f]' | awk '{print $1}' | head -1)
echo "mesh kc pod: $KCPOD"
echo "=== mesh keycloak env (relative path? admin var names?) ==="
kubectl -n "$GWNS" get pod "$KCPOD" -o jsonpath='{range .spec.containers[0].env[*]}{.name}{"\n"}{end}' 2>&1 | grep -avi memcache | grep -iE 'ADMIN|BOOTSTRAP|RELATIVE|HOSTNAME|HTTP'
echo "=== realms in the MESH keycloak ==="
kubectl -n "$GWNS" exec "$KCPOD" -- sh -lc 'KA=${KC_BOOTSTRAP_ADMIN_USERNAME:-${KEYCLOAK_ADMIN:-admin}}; KP=${KC_BOOTSTRAP_ADMIN_PASSWORD:-${KEYCLOAK_ADMIN_PASSWORD:-admin}}; for base in http://localhost:8080/keycloak http://localhost:8080; do /opt/keycloak/bin/kcadm.sh config credentials --server $base --realm master --user "$KA" --password "$KP" >/dev/null 2>&1 && { echo "base=$base"; /opt/keycloak/bin/kcadm.sh get realms --fields realm 2>/dev/null; break; }; done' 2>&1 | grep -avi memcache | grep -iE 'realm|base=' | head -20
echo "=== mesh keycloak svc ==="
kubectl -n "$GWNS" get svc 2>&1 | grep -avi memcache | grep -i keycloak | head
echo "=== the mesh oauth2-proxy for an existing org (poc2) — what client/realm does IT use? (a working reference) ==="
kubectl get authorizationpolicy -A >/dev/null 2>&1
kubectl -n "$GWNS" get deploy 2>&1 | grep -avi memcache | grep -iE 'oauth2|portal' | head
echo DONE
