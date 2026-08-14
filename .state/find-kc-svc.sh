cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
echo "--- keycloak svc in platform-mesh-system ---"
kubectl -n platform-mesh-system get svc -o wide 2>&1 | grep -avi memcache | grep -i keycloak
