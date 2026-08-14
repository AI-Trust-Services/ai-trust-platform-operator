#!/bin/bash
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh 2>/dev/null; load_config 2>/dev/null
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
f(){ grep -avi memcache; }

# Prove the backend's NEW auth path works: mesh admin token can create a user in realm fridaytest.
# (This is exactly what users-backend._fetch_token + admin_client(current_realm='fridaytest') now do.)
KCU=$(kubectl -n "$NS" get secret mesh-keycloak-admin -o jsonpath='{.data.username}' | base64 -d)
KCP=$(kubectl -n "$NS" get secret mesh-keycloak-admin -o jsonpath='{.data.password}' | base64 -d)
INNER='K=/opt/keycloak/bin/kcadm.sh
$K config credentials --server http://localhost:8080/keycloak --realm master --user "$U" --password "$P" >/dev/null 2>&1
echo "=== create test user in realm fridaytest (mesh-admin path) ==="
$K create users -r fridaytest -s username=e2e-tenant-check@example.com -s email=e2e-tenant-check@example.com -s enabled=true 2>&1 | tail -2 || echo "  (may already exist)"
echo "=== users now in fridaytest ==="
$K get users -r fridaytest --fields username 2>/dev/null
echo "=== confirm it did NOT leak into poc2 ==="
$K get users -r poc2 -q username=e2e-tenant-check@example.com --fields username 2>/dev/null || echo "  (not in poc2 — correct)"
echo "=== cleanup: delete the test user from fridaytest ==="
UID=$($K get users -r fridaytest -q username=e2e-tenant-check@example.com --fields id --format csv --noquotes 2>/dev/null | head -1)
[ -n "$UID" ] && $K delete users/$UID -r fridaytest 2>&1 | tail -1 && echo "  deleted $UID"'
kubectl -n platform-mesh-system exec -i keycloak-0 -- env U="$KCU" P="$KCP" sh -c "$INNER" 2>&1 | f
echo DONE
