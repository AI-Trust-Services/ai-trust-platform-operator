cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh
load_config
export KUBECONFIG=""
kubectl -n aitrust-mt-msp get pods 2>&1 | grep -avi memcache
