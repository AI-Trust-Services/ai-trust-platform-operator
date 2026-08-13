#!/bin/bash
# Comprehensive config audit for the MT shared-app deployment
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp; GWNS=platform-mesh-system; LB=130.214.18.166
H=ai-trust-mt.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu
line(){ echo "======================================================================"; echo "== $1"; echo "======================================================================"; }

line "1. WORKLOAD PODS in $NS (all Running/Ready?)"
kubectl -n "$NS" get pods --no-headers 2>/dev/null | grep -avi memcache | awk '{printf "%-52s %-8s %s\n",$1,$2,$3}'

line "2. OAUTH2-PROXY final args (auth wiring)"
kubectl -n "$NS" get deploy oauth2-proxy -o jsonpath='{range .spec.template.spec.containers[0].args[*]}{@}{"\n"}{end}' 2>&1 | grep -avi memcache

line "3. DATABASE_URL role on each backend (RLS: must be non-superuser ai_trust_app, NOT postgres)"
for d in $(kubectl -n "$NS" get deploy -o name 2>/dev/null | grep -avi memcache); do
  U=$(kubectl -n "$NS" get "$d" -o jsonpath='{range .spec.template.spec.containers[0].env[?(@.name=="DATABASE_URL")]}{.value}{end}' 2>/dev/null)
  [ -n "$U" ] && echo "$(basename $d): $(echo "$U" | sed -E 's#(postgresql[^:]*://)([^:]+):[^@]*@#\1\2:***@#')"
done

line "4. TENANCY + OPENFGA + KEYCLOAK env on backends (sample: registry)"
kubectl -n "$NS" get deploy registry -o jsonpath='{range .spec.template.spec.containers[0].env[*]}{.name}={.value}{"\n"}{end}' 2>&1 | grep -avi memcache | grep -iE 'TENANCY_MODE|OPENFGA_URL|OPENFGA_STORE_ID|KEYCLOAK_URL|KEYCLOAK_REALM'

line "5. OPENFGA store id consistency across ALL backends"
for d in $(kubectl -n "$NS" get deploy -o name 2>/dev/null | grep -avi memcache); do
  S=$(kubectl -n "$NS" get "$d" -o jsonpath='{range .spec.template.spec.containers[0].env[?(@.name=="OPENFGA_STORE_ID")]}{.value}{end}' 2>/dev/null)
  [ -n "$S" ] && echo "$(basename $d): OPENFGA_STORE_ID=$S"
done
echo DONE_AUDIT1
