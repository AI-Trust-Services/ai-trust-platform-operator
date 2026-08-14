cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"

# 1. Read mesh admin creds (do NOT print them)
KC_USER=$(kubectl -n aitrust-mt-msp get secret mesh-keycloak-admin -o jsonpath='{.data.username}' 2>/dev/null | base64 -d)
KC_PASS=$(kubectl -n aitrust-mt-msp get secret mesh-keycloak-admin -o jsonpath='{.data.password}' 2>/dev/null | base64 -d)

if [ -z "$KC_USER" ] || [ -z "$KC_PASS" ]; then
  echo "ERROR: could not read mesh-keycloak-admin creds"
  echo "--- secret keys present ---"
  kubectl -n aitrust-mt-msp get secret mesh-keycloak-admin -o jsonpath='{.data}' 2>&1 | tr ',' '\n' | sed 's/:.*//' 
  exit 1
fi
echo "creds read OK (user len=${#KC_USER}, pass len=${#KC_PASS})"

# 2. Mint short-lived admin token INSIDE keycloak-0 pod
TOKEN=$(kubectl -n platform-mesh-system exec keycloak-0 -- env U="$KC_USER" P="$KC_PASS" sh -c '
  /opt/keycloak/bin/kcadm.sh config credentials --server http://localhost:8080 --realm master --user "$U" --password "$P" >/dev/null 2>&1
  cat ~/.keycloak/kcadm.config 2>/dev/null
' 2>/dev/null | tr -d "\r" | python3 -c "import sys,json; d=json.load(sys.stdin); import re; 
# kcadm.config structure: endpoints -> server -> realm -> {token,...}
eps=d.get('endpoints',{});
tok=''
for srv,realms in eps.items():
    for rlm,info in realms.items():
        if isinstance(info,dict) and info.get('token'):
            tok=info['token']
print(tok)" 2>/dev/null)

if [ -z "$TOKEN" ]; then
  echo "ERROR: could not mint token; dumping kcadm.config structure keys"
  kubectl -n platform-mesh-system exec keycloak-0 -- env U="$KC_USER" P="$KC_PASS" sh -c '
    /opt/keycloak/bin/kcadm.sh config credentials --server http://localhost:8080 --realm master --user "$U" --password "$P" >/dev/null 2>&1
    cat ~/.keycloak/kcadm.config 2>/dev/null' 2>/dev/null | tr -d "\r" | python3 -c "import sys,json;d=json.load(sys.stdin);print(list(d.keys()));print(list(d.get('endpoints',{}).keys()))" 2>&1
  exit 1
fi
echo "token minted OK (len=${#TOKEN})"

# stash token to a temp file for the curl-pod step
echo "$TOKEN" > /tmp/kc_token.txt
echo "TOKEN_SAVED"
