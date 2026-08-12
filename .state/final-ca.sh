cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
exec > .state/final-ca.out 2>&1

echo "===== domain-certificate-ca: raw decode cert counts (robust) ====="
kubectl -n platform-mesh-system get secret domain-certificate-ca -o yaml 2>&1 | grep -avi memcache > /tmp/dcca.yaml
for k in ca.crt tls.crt; do
  v=$(grep -E "^  $k:" /tmp/dcca.yaml | awk '{print $2}')
  if [ -n "$v" ]; then
    echo "key=$k -> $(echo "$v" | base64 -d 2>/dev/null | grep -c 'BEGIN CERTIFICATE') certs; subjects:"
    echo "$v" | base64 -d 2>/dev/null | openssl storeutl -noout -text -certs /dev/stdin 2>/dev/null | grep -iE 'Subject:' | head
  fi
done
echo
echo "===== iam-service logs: WAC / authentication / apply / certificateAuthority ====="
kubectl -n platform-mesh-system logs deploy/iam-service --since=48h 2>&1 | grep -avi memcache | grep -iE 'workspaceauthentication|authenticationconfig|certificateauthorit|apply|realm|poc|onboard|ca ' | tail -40
echo
echo "===== iam-service logs tail (context) ====="
kubectl -n platform-mesh-system logs deploy/iam-service --since=2h --tail=30 2>&1 | grep -avi memcache
