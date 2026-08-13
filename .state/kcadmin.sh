#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
KCPOD=$(kubectl -n "$NS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep '^keycloak-[0-9a-f]' | awk '{print $1}' | head -1)
echo "kc pod: $KCPOD"
echo "=== deterministically create the admin via KC's bootstrap-admin user command (KC25) ==="
# kc.sh bootstrap-admin user --bootstrap-admin-username admin --bootstrap-admin-password admin  (KC26)
# KC25.0.6: use the add-user-keycloak fallback OR kcadm create against the running server with the
# master temp admin. Simplest deterministic path on KC25: kc.sh bootstrap-admin recovery is not present,
# so use kcadm.sh with the running server after enabling a temp admin. Instead: create via kcadm using
# the KC container's local admin creation utility.
kubectl -n "$NS" exec "$KCPOD" -- sh -lc '
  /opt/keycloak/bin/kcadm.sh config credentials --server http://localhost:8080/keycloak --realm master --user admin --password admin 2>&1 | head -3 || true
  echo "--- if the above failed with 401/403, create the admin directly: ---"
  /opt/keycloak/bin/kc.sh bootstrap-admin user --bootstrap-admin-username admin --bootstrap-admin-password admin 2>&1 | tail -5 || echo "bootstrap-admin subcommand not available on this KC version"
' 2>&1 | grep -avi memcache | tail -15
echo DONE
