#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp; GWNS=platform-mesh-system
REG=ai-system-registry-backend
line(){ echo "== $1 =="; }

line "4b. TENANCY/OPENFGA/KEYCLOAK env on $REG"
kubectl -n "$NS" get deploy "$REG" -o jsonpath='{range .spec.template.spec.containers[0].env[*]}{.name}={.value}{"\n"}{end}' 2>&1 | grep -avi memcache | grep -iE 'TENANCY|OPENFGA|KEYCLOAK|INITIAL_ADMIN|X-Forwarded'

STOREID=$(kubectl -n "$NS" get deploy "$REG" -o jsonpath='{range .spec.template.spec.containers[0].env[?(@.name=="OPENFGA_STORE_ID")]}{.value}{end}' 2>/dev/null)
echo "STOREID=$STOREID"

line "6b. OpenFGA store contents + all 6 role checks + who is admin"
kubectl -n "$NS" run fga-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet --command -- \
  sh -c "
    B=http://openfga.$GWNS.svc.cluster.local:8080
    echo '-- read ALL tuples in store (roles + user grants) --'
    curl -s -X POST \$B/stores/$STOREID/read -H 'content-type: application/json' -d '{}' | tr ',' '\n' | grep -iE 'user|relation|object' | head -60
  " 2>&1 | grep -avi memcache

line "10. What identity does the app see? users-backend env (KEYCLOAK realm/client for user mgmt)"
kubectl -n "$NS" get deploy users-backend -o jsonpath='{range .spec.template.spec.containers[0].env[*]}{.name}={.value}{"\n"}{end}' 2>&1 | grep -avi memcache | grep -iE 'KEYCLOAK|OPENFGA|CLIENT|REALM|INITIAL_ADMIN'
echo DONE_AUDIT3
