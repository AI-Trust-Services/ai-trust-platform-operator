cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
exec > .state/ca-secrets.out 2>&1

echo "===== domain-certificate-ca secret: cert count in ca.crt ====="
kubectl -n platform-mesh-system get secret domain-certificate-ca -o jsonpath='{.data}' 2>&1 | grep -avi memcache | tr ',' '\n' | grep -oE '"[^"]+":' | head
echo "--- keys above; now decode each data key and count BEGIN CERTIFICATE ---"
for k in tls.crt ca.crt cert.pem ca.pem; do
  v=$(kubectl -n platform-mesh-system get secret domain-certificate-ca -o jsonpath="{.data.$k}" 2>/dev/null | grep -avi memcache)
  if [ -n "$v" ]; then
    n=$(echo "$v" | base64 -d 2>/dev/null | grep -c "BEGIN CERTIFICATE")
    echo "domain-certificate-ca key=$k certs=$n"
  fi
done
echo
echo "===== all secrets in platform-mesh-system whose data contains the self-signed CA (search by known serial fragment) ====="
echo "--- list secrets ---"
kubectl -n platform-mesh-system get secret -o name 2>&1 | grep -avi memcache | grep -iE 'ca|cert|domain|keycloak|oidc|trust'
