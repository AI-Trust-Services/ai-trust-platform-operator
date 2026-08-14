#!/bin/bash
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh 2>/dev/null; load_config 2>/dev/null
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
f(){ grep -avi memcache; }

# Read mesh KC admin creds and pass them to kcadm INSIDE the pod via stdin env, not argv.
KCU=$(kubectl -n "$NS" get secret mesh-keycloak-admin -o jsonpath='{.data.username}' | base64 -d)
KCP=$(kubectl -n "$NS" get secret mesh-keycloak-admin -o jsonpath='{.data.password}' | base64 -d)

# Inner script runs in keycloak-0. It reads U and P from env (piped via kubectl exec env),
# authenticates with kcadm, and prints ONLY username/email/enabled for the two realms.
INNER='K=/opt/keycloak/bin/kcadm.sh
$K config credentials --server http://localhost:8080/keycloak --realm master --user "$U" --password "$P" >/dev/null 2>&1 || \
$K config credentials --server http://localhost:8080 --realm master --user "$U" --password "$P" >/dev/null 2>&1
for R in fridaytest mirceatest; do
  echo "=== realm $R users ==="
  $K get users -r "$R" --fields username,email,enabled,emailVerified 2>/dev/null || echo "  (query failed for $R)"
  echo
done'

# Pass creds as env into the exec (argv of the remote shell is just "sh -c <script>"; creds are in env, not argv).
kubectl -n platform-mesh-system exec -i keycloak-0 -- env U="$KCU" P="$KCP" sh -c "$INNER" 2>&1 | f
echo DONE
