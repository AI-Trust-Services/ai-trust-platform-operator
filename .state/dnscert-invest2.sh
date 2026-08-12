#!/bin/bash
# READ-ONLY investigation of current DNS/cert/auth state. NO changes. Fresh mint; no python; robust probes.
exec > /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP/.state/dnscert-invest2.out 2>&1
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
rm -f "$SHOOT_KUBECONFIG"; mint_shoot_kubeconfig || { echo LOGIN_EXPIRED; exit 3; }
export KUBECONFIG="$SHOOT_KUBECONFIG"
SUF="ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu"
LB=130.214.18.166
GWNS=platform-mesh-system

echo "############ 1. CERT SERVED NOW (apex + instances) — via openssl in a pod that has it ############"
for H in "$SUF" "testai.$SUF" "q3c0weh7suf5hgjk-my-aitrust.$SUF"; do
  echo "--- $H ---"
  kubectl -n "$GWNS" run p-$RANDOM --rm -i --restart=Never --image=alpine/openssl:latest --quiet -- \
    sh -c "echo | openssl s_client -connect $LB:443 -servername $H 2>/dev/null | openssl x509 -noout -issuer -subject -enddate" 2>&1 | grep -avi memcache | grep -iE 'issuer|subject|notAfter'
done

echo
echo "############ 2. PLATFORM AUTH HEALTH (frontproxy x509/TokenReview) ############"
FP=$(kubectl -n "$GWNS" get deploy -o name 2>/dev/null | grep -avi memcache | grep -iE 'front-proxy|frontproxy' | head -1)
echo "frontproxy deploy: $FP"
[ -n "$FP" ] && kubectl -n "$GWNS" logs "$FP" --tail=250 2>&1 | grep -avi memcache | grep -iE 'x509|unknown authority|TokenReview|oidc authenticator' | tail -8 || echo "  (none / no deploy match)"

echo
echo "############ 3. domain-certificate SECRET issuer (self-signed vs LE) ############"
kubectl -n "$GWNS" get secret domain-certificate -o jsonpath='{.data.tls\.crt}' 2>/dev/null | base64 -d 2>/dev/null > /tmp/dc.crt
openssl x509 -in /tmp/dc.crt -noout -issuer -subject -enddate 2>&1 | grep -avi memcache || echo "  (unreadable)"

echo
echo "############ 4. gardener Certificate CRs (state + secret + dnsNames) ############"
kubectl -n "$GWNS" get certificate.cert.gardener.cloud -o custom-columns='NAME:.metadata.name,STATE:.status.state,SECRET:.spec.secretRef.name,DNS:.spec.commonName' 2>&1 | grep -avi memcache | head -20

echo
echo "############ 5. GATEWAY listeners -> certRefs (no python) ############"
kubectl -n "$GWNS" get gateway k8sapi-gateway \
  -o jsonpath='{range .spec.listeners[*]}{.name}{"  host="}{.hostname}{"  cert="}{.tls.certificateRefs[*].name}{"\n"}{end}' 2>&1 | grep -avi memcache

echo
echo "############ 6. PUBLIC DNS: apex + a random instance host both resolve to LB $LB ? ############"
for H in "$SUF" "randomxyz123.$SUF"; do
  R=$(kubectl -n "$GWNS" run d-$RANDOM --rm -i --restart=Never --image=alpine/openssl:latest --quiet -- \
    sh -c "getent hosts $H || nslookup $H 2>/dev/null | grep -i address | tail -1" 2>&1 | grep -avi memcache | tr -d '\r')
  echo "  $H -> $R"
done

echo
echo "############ 7. gateway ownership (flux/helm labels) ############"
kubectl -n "$GWNS" get gateway k8sapi-gateway -o jsonpath='{.metadata.annotations}{"\n"}' 2>&1 | grep -avi memcache | tr ',' '\n' | grep -iE 'helm|flux|managed-by|reconcile|kustomize' | head

echo
echo "############ 8. is cert-aitrust-full (the full-SAN LE) still present + Ready? ############"
kubectl -n "$GWNS" get certificate.cert.gardener.cloud cert-aitrust-full -o jsonpath='state={.status.state} secret={.spec.secretRef.name} exp={.status.expirationTimestamp}{"\n"}' 2>&1 | grep -avi memcache || echo "  (absent)"
kubectl -n "$GWNS" get secret cert-aitrust-full >/dev/null 2>&1 && echo "  secret cert-aitrust-full EXISTS" || echo "  secret cert-aitrust-full ABSENT"
echo DONE
