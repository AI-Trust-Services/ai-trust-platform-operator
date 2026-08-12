#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
exec > .state/inv7-castore.out 2>&1
K(){ kubectl "$@" 2>&1 | grep -avi memcache; }

echo "############ domain-certificate-ca secret: decode (this is the mesh CA the WAC pins) ############"
for KEYNAME in tls.crt ca.crt; do
  V="$(K -n "$MESH_NS" get secret domain-certificate-ca -o jsonpath="{.data.$(echo $KEYNAME | sed 's/\./\\./')}" 2>/dev/null)"
  if [ -n "$V" ]; then
    echo "--- key: $KEYNAME ---"
    echo "$V" | base64 -d > /tmp/dcca.pem 2>/dev/null
    openssl x509 -in /tmp/dcca.pem -noout -subject -issuer -fingerprint 2>&1 | head
  fi
done
echo "(WAC pinned CA SHA1 was 08:53:2F:3B:C9:24:7B:86:64:35:CD:BB:A3:5E:FA:A4:82:7C:9B:2D)"

echo; echo "############ account-operator full env (looking for a CA/issuer value it stamps into WAC) ############"
K -n "$MESH_NS" get deploy account-operator -o jsonpath='{range .spec.template.spec.containers[0].env[*]}ENV {.name}={.value}{"\n"}{end}' 2>&1 | grep -avi memcache

echo; echo "############ account-operator config configmaps ############"
K -n "$MESH_NS" get cm | grep -aiE 'account-operator|account_operator' | grep -avi memcache
for c in $(K -n "$MESH_NS" get cm -o name 2>/dev/null | grep -aiE 'account-operator'); do
  echo "=== $c ==="
  K -n "$MESH_NS" get "$c" -o yaml 2>&1 | grep -avi managedFields | grep -aiE 'ca|issuer|keycloak|oidc|cert|url|domain|authentication' | head -40
done

echo; echo "############ infra HR: find the block that templates WorkspaceAuthenticationConfiguration / orgs-authentication ############"
K -n "$MESH_NS" get helmrelease infra -o yaml 2>&1 | grep -avi managedFields | grep -aiE -B2 -A6 'orgs-authentication|WorkspaceAuthentication|claims.email|realms/welcome' | head -60

echo; echo "############ Is orgs-authentication (root WAC) helm/flux-owned or hand-applied? check ownerRefs/annotations via kcp ############"
setup_kcp; kcp_portforward
kc root get workspaceauthenticationconfiguration orgs-authentication -o jsonpath='{.metadata.annotations}{"\n"}{.metadata.ownerReferences}{"\n"}' 2>&1 | grep -avi memcache
