#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
LB=130.214.18.166
H=testai.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu
echo "=== clean issuer read for testai (single pod, full openssl) ==="
sk -n platform-mesh-system run iss-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet -- \
  sh -c "echo Q | openssl s_client -connect $LB:443 -servername $H 2>/dev/null | openssl x509 -noout -issuer -subject" 2>&1 | grep -aiE 'issuer|subject'
echo "=== does cert-p1 secret exist in the SAME namespace as the gateway, and is a ReferenceGrant needed? ==="
echo "gateway ns=platform-mesh-system ; cert-p1 ns=platform-mesh-system (same ns -> no ReferenceGrant needed)"
echo "=== testai routes: confirm they are ONLY on terminate-testai now (not also wildstar) ==="
for r in aitp-33hins0iklcwfg45-testai-app aitp-33hins0iklcwfg45-testai-keycloak; do
  echo "$r sections=$(sk -n platform-mesh-system get httproute "$r" -o jsonpath='{range .spec.parentRefs[*]}{.sectionName}{" "}{end}' 2>/dev/null)"
done
echo "=== terminate-testai listener attachedRoutes + conditions ==="
sk -n platform-mesh-system get gateway k8sapi-gateway -o jsonpath='{range .status.listeners[?(@.name=="terminate-testai")]}attachedRoutes={.attachedRoutes} programmed={.conditions[?(@.type=="Programmed")].status} resolvedRefs={.conditions[?(@.type=="ResolvedRefs")].status} reason={.conditions[?(@.type=="ResolvedRefs")].reason}{"\n"}{end}' 2>&1 | grep -av memcache
