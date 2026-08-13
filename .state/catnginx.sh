#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
kubectl -n "$NS" exec deploy/shell -- sh -lc 'cat /etc/nginx/conf.d/default.conf 2>/dev/null || cat /etc/nginx/nginx.conf' 2>&1 | grep -avi memcache
