#!/bin/bash
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh 2>/dev/null; load_config 2>/dev/null
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
f(){ grep -avi memcache; }

BASE=https://ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu/keycloak/realms

echo "===== Can users-backend fetch the JWKS the way PyJWKClient does (urllib, default TLS verify)? ====="
PY='import urllib.request,ssl,json,sys
for realm in ("fridaytest","mirceatest"):
    url="'"$BASE"'/%s/protocol/openid-connect/certs"%realm
    try:
        r=urllib.request.urlopen(url,timeout=6)   # default context = verify TLS, like PyJWKClient
        d=json.loads(r.read().decode())
        print("OK  ",realm,"keys=",len(d.get("keys",[])))
    except Exception as e:
        print("FAIL",realm,type(e).__name__, str(e)[:160])'
kubectl -n "$NS" exec deploy/users-backend -- python -c "$PY" 2>&1 | f

echo; echo "===== Same URL but ignoring TLS (proves it is specifically a cert-trust failure) ====="
PY2='import urllib.request,ssl,json
ctx=ssl.create_default_context(); ctx.check_hostname=False; ctx.verify_mode=ssl.CERT_NONE
for realm in ("fridaytest","mirceatest"):
    url="'"$BASE"'/%s/protocol/openid-connect/certs"%realm
    try:
        r=urllib.request.urlopen(url,timeout=6,context=ctx)
        d=json.loads(r.read().decode()); print("OK-noTLS",realm,"keys=",len(d.get("keys",[])))
    except Exception as e:
        print("FAIL-noTLS",realm,type(e).__name__,str(e)[:160])'
kubectl -n "$NS" exec deploy/users-backend -- python -c "$PY2" 2>&1 | f

echo; echo "===== Does the backend trust store contain the mesh CA? (REQUESTS_CA_BUNDLE / SSL_CERT_FILE) ====="
kubectl -n "$NS" get deploy users-backend -o jsonpath='{range .spec.template.spec.containers[0].env[*]}{.name}={.value}{"\n"}{end}' 2>&1 | f | grep -iE 'CA_BUNDLE|SSL_CERT|CERT_FILE|REQUESTS' || echo "  (no CA env — uses system trust store, which lacks the mesh self-signed CA)"
echo DONE
