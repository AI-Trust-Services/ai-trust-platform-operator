cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
exec > .state/iam-onboard.out 2>&1

echo "===== iam-service deploy: args/env/mounts (CA) ====="
kubectl -n platform-mesh-system get deploy iam-service -o yaml 2>&1 | grep -avi memcache | grep -iE 'name:|image:|--|value:|mountPath|secretName|configMap|claim|args|env|domain|ca|cert|keycloak|issuer|realm'
echo
echo "===== iam-service HelmRelease values (CA/onboarding/WAC) ====="
kubectl -n platform-mesh-system get helmrelease iam-service -o yaml 2>&1 | grep -avi memcache | sed -n '/values:/,/status:/p'
echo
echo "===== domain-certificate-ca secret: decode ca.crt + tls.crt cert counts ====="
for k in ca.crt tls.crt; do
  v=$(kubectl -n platform-mesh-system get secret domain-certificate-ca -o jsonpath="{.data.$k}" 2>/dev/null | grep -avi memcache)
  if [ -n "$v" ]; then
    n=$(echo "$v" | base64 -d 2>/dev/null | grep -c "BEGIN CERTIFICATE")
    echo "domain-certificate-ca key=$k certs=$n"
  fi
done
echo
echo "===== any Job/CronJob/initcontainer that applies WAC? look for onboarding jobs ====="
kubectl -n platform-mesh-system get jobs,cronjobs 2>&1 | grep -avi memcache
