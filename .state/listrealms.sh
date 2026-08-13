#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
GWNS=platform-mesh-system
KCPOD=$(kubectl -n "$GWNS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep -E '^keycloak-[0-9]' | awk '{print $1}' | head -1)
echo "=== mesh realms (which of testmt2/poc2/aitrustmt/mttest2 exist?) ==="
kubectl -n "$GWNS" exec "$KCPOD" -- sh -lc '
KA=${KC_BOOTSTRAP_ADMIN_USERNAME:-admin}; KP=${KC_BOOTSTRAP_ADMIN_PASSWORD:-admin}
/opt/keycloak/bin/kcadm.sh config credentials --server http://localhost:8080/keycloak --realm master --user "$KA" --password "$KP" >/dev/null 2>&1
/opt/keycloak/bin/kcadm.sh get realms --fields realm 2>/dev/null
' 2>&1 | grep -avi memcache | grep -iE 'realm' | head -40
echo DONE
