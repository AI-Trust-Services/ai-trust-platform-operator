#!/bin/bash
# login.sh — run ONCE in your Ubuntu terminal before deploy:
#   bash /mnt/c/claude/projects/eu-ai-trust-platform/Standard_Ai_Platform/prerequisites/login.sh
# Completes the garden OIDC browser login so the deploy scripts can mint a payload-cluster admin
# kubeconfig (currently the ai-trust-1 shoot). Re-run if Claude reports "adminkubeconfig failed / access expired".
export PATH=/home/mircea/.local/bin:/usr/local/bin:/usr/bin:/bin
export KUBECONFIG=/mnt/c/claude/projects/eu-ai-trust-platform/config/kubeconfig-garden-ai-trust.yaml
echo ">>> Logging into garden (a browser opens, OR a http://localhost:8000/ URL is printed — log in with SAP creds)."
echo ""
kubectl get shoot ai-trust-1 -n garden-ai-trust -o name
echo ""
echo ">>> If the shoot name shows above, the login is cached. Go back to Claude and say 'go'."
