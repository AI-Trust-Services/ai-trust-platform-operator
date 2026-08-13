cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh
load_config
export KUBECONFIG=""
echo "=== NAMESPACES matching aitrust/mt/msp ==="
kubectl get ns 2>&1 | grep -avi memcache | grep -iE "aitrust|mt|msp"
echo "=== all pods across cluster matching keycloak/oauth2/shell ==="
kubectl get pods -A 2>&1 | grep -avi memcache | grep -iE "keycloak|oauth2|shell" | head -40
