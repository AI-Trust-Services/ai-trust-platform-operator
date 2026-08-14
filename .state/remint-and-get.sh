cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"

KC_USER=$(kubectl -n aitrust-mt-msp get secret mesh-keycloak-admin -o jsonpath='{.data.username}' | base64 -d)
KC_PASS=$(kubectl -n aitrust-mt-msp get secret mesh-keycloak-admin -o jsonpath='{.data.password}' | base64 -d)

# Mint fresh token INSIDE keycloak-0, using the correct base path /keycloak
TOKEN=$(kubectl -n platform-mesh-system exec keycloak-0 -- env U="$KC_USER" P="$KC_PASS" sh -c '
  /opt/keycloak/bin/kcadm.sh config credentials --server http://localhost:8080/keycloak --realm master --user "$U" --password "$P" >/dev/null 2>&1
  cat ~/.keycloak/kcadm.config 2>/dev/null
' 2>/dev/null | tr -d "\r" | python3 -c "
import sys,json
d=json.load(sys.stdin)
tok=''
for srv,realms in d.get('endpoints',{}).items():
    for rlm,info in realms.items():
        if isinstance(info,dict) and info.get('token'):
            tok=info['token']
print(tok)")

if [ -z "$TOKEN" ]; then echo 'ERROR: no token'; exit 1; fi
echo "fresh token minted (len=${#TOKEN})"
echo "$TOKEN" > /tmp/kc_token.txt

KC="http://keycloak-service.platform-mesh-system.svc.cluster.local:8080/keycloak"
REALM="fridaytest"
CLIENTID="aitrust-mt-app"

kubectl -n aitrust-mt-msp run kc-getc2-$$ --rm -i --restart=Never \
  --image=curlimages/curl:8.9.1 \
  --env="TOKEN=$TOKEN" --env="KC=$KC" --env="REALM=$REALM" --env="CLIENTID=$CLIENTID" \
  --command -- sh -c '
    echo "=== token check (list realm names) ==="
    curl -s -H "Authorization: Bearer $TOKEN" "$KC/admin/realms" -w "\nHTTP %{http_code}\n" -o /tmp/r.json
    grep -o "\"realm\":\"[^\"]*\"" /tmp/r.json | tr "\n" " "; echo ""
    echo "=== CLIENT REP (clientId=$CLIENTID, realm=$REALM) ==="
    curl -s -H "Authorization: Bearer $TOKEN" "$KC/admin/realms/$REALM/clients?clientId=$CLIENTID" -w "\nHTTP %{http_code}\n"
  ' 2>&1 | grep -avi memcache
