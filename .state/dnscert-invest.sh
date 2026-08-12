#!/bin/bash
# READ-ONLY investigation of the current DNS/cert/auth state. Makes NO changes.
exec > /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP/.state/dnscert-invest.out 2>&1
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
[ -s "$SHOOT_KUBECONFIG" ] || mint_shoot_kubeconfig || { echo LOGIN_EXPIRED; exit 3; }
SUF="ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu"
LB=130.214.18.166
GWNS=platform-mesh-system

echo "############ 1. WHAT CERT IS SERVED RIGHT NOW (apex + each live instance) ############"
for H in "$SUF" "testai.$SUF" "q3c0weh7suf5hgjk-my-aitrust.$SUF"; do
  echo "--- $H ---"
  kubectl -n "$GWNS" run p-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet -- \
    sh -c "echo | openssl s_client -connect $LB:443 -servername $H 2>/dev/null | openssl x509 -noout -issuer -subject -dates 2>/dev/null" 2>&1 | grep -avi memcache | grep -E 'issuer|subject|notAfter'
done

echo
echo "############ 2. IS PLATFORM AUTH HEALTHY RIGHT NOW (the thing that broke last time) ############"
echo "--- frontproxy recent x509 / TokenReview errors (expect NONE if self-signed baseline) ---"
FP=$(kubectl -n "$GWNS" get deploy -o name 2>/dev/null | grep -avi memcache | grep -iE 'front-proxy|frontproxy' | head -1)
echo "frontproxy: $FP"
kubectl -n "$GWNS" logs "$FP" --tail=200 2>&1 | grep -avi memcache | grep -iE 'x509|unknown authority|TokenReview|oidc authenticator' | tail -8 || echo "  (no x509/TokenReview errors)"

echo
echo "############ 3. THE domain-certificate SECRET — self-signed or LE right now? ############"
kubectl -n "$GWNS" get secret domain-certificate -o jsonpath='{.data.tls\.crt}' 2>/dev/null | base64 -d 2>/dev/null \
  | openssl x509 -noout -issuer -subject -enddate 2>/dev/null | grep -avi memcache || echo "  (could not read)"

echo
echo "############ 4. MANAGED CERT CRs present (cert-p1 / cert-aitrust-full / domain-certificate) ############"
kubectl -n "$GWNS" get certificate.cert.gardener.cloud 2>&1 | grep -avi memcache | head -20

echo
echo "############ 5. GATEWAY listeners + which secret each certRef points at ############"
kubectl -n "$GWNS" get gateway k8sapi-gateway -o json 2>/dev/null | grep -avi memcache \
  | python3 -c 'import sys,json; g=json.load(sys.stdin); [print(f"  {l[\"name\"]:24} host={l.get(\"hostname\",\"-\"):40} certRefs={[r[\"name\"] for r in l.get(\"tls\",{}).get(\"certificateRefs\",[])]}") for l in g["spec"]["listeners"]]' 2>&1 | grep -avi memcache

echo
echo "############ 6. PUBLIC DNS resolution (does *.suffix resolve to the LB?) ############"
for H in "$SUF" "randomxyz.$SUF"; do
  kubectl -n "$GWNS" run d-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet -- \
    sh -c "nslookup $H 2>/dev/null | tail -4" 2>&1 | grep -avi memcache | grep -E 'Name|Address|$H' | head -3
  echo "  ^ $H"
done

echo
echo "############ 7. GATEWAY OWNERSHIP (Flux/Helm) — who reconciles k8sapi-gateway ############"
kubectl -n "$GWNS" get gateway k8sapi-gateway -o jsonpath='{.metadata.labels}{"\n"}{.metadata.annotations}{"\n"}' 2>&1 | grep -avi memcache | tr ',' '\n' | grep -iE 'helm|flux|managed-by|release|kustomize' | head
echo DONE
