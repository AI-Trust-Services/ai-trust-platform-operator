#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
KCPOD=$(kubectl -n "$NS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep '^keycloak-[0-9a-f]' | awk '{print $1}' | head -1)
echo "=== A) token via LOCALHOST inside the KC pod (does admin exist & work?) ==="
kubectl -n "$NS" exec "$KCPOD" -- sh -lc 'curl -s -o /dev/null -w "localhost: http=%{http_code}\n" -d "client_id=admin-cli&username=admin&password=admin&grant_type=password" http://localhost:8080/keycloak/realms/master/protocol/openid-connect/token' 2>&1 | grep -avi memcache | grep http=
echo "=== B) token via the SERVICE DNS from inside the KC pod (same host the provisioner uses) ==="
kubectl -n "$NS" exec "$KCPOD" -- sh -lc 'curl -s -o /dev/null -w "svc-dns: http=%{http_code}\n" -d "client_id=admin-cli&username=admin&password=admin&grant_type=password" http://keycloak.aitrust-mt-msp.svc.cluster.local:8080/keycloak/realms/master/protocol/openid-connect/token' 2>&1 | grep -avi memcache | grep http=
echo "=== C) token via short 'keycloak:8080' (what the shared-app provision job uses) ==="
kubectl -n "$NS" exec "$KCPOD" -- sh -lc 'curl -s -o /dev/null -w "short: http=%{http_code}\n" -d "client_id=admin-cli&username=admin&password=admin&grant_type=password" http://keycloak:8080/keycloak/realms/master/protocol/openid-connect/token' 2>&1 | grep -avi memcache | grep http=
echo "=== if svc-dns/short differ from localhost → it's KC_HOSTNAME_ADMIN/frontend-url hostname enforcement ==="
echo DONE
