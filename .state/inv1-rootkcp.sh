#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
exec > .state/inv1-rootkcp.out 2>&1
K(){ kubectl "$@" 2>&1 | grep -avi memcache; }

echo "############ PODS in $MESH_NS matching root/kcp/shard/proxy ############"
K -n "$MESH_NS" get pods | grep -iE 'root|kcp|shard|proxy|front'

echo; echo "############ CRDs matching authentication/oidc/kcp/workspace ############"
K get crd | grep -iE 'authentication|oidc|kcp|workspace|shard'

echo; echo "############ RootShard CR (operator.kcp.io) ############"
K -n "$MESH_NS" get rootshard -o yaml 2>&1 | grep -avi 'managedFields' | head -200

echo; echo "############ FrontProxy CR ############"
K -n "$MESH_NS" get frontproxy -o yaml 2>&1 | grep -avi 'managedFields' | head -150
