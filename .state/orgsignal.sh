#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
kubectl get ns >/dev/null 2>&1 || { echo "KUBECONFIG_EXPIRED"; exit 7; }
NS=aitrust-mt-msp

echo "=== 1. FULL metadata of one synced Subscription (labels+annotations+owner) ==="
row=$(kubectl get subscriptions.sub.aitrustmt.msp -A -o jsonpath='{.items[0].metadata.namespace}/{.items[0].metadata.name}' 2>/dev/null | grep -avi memcache)
ns=${row%/*}; nm=${row#*/}
echo "CR: $ns/$nm"
kubectl -n "$ns" get subscriptions.sub.aitrustmt.msp "$nm" -o jsonpath='LABELS:{"\n"}{range .metadata.labels}{"  "}{@}{"\n"}{end}{"\n"}ANNOTATIONS:{"\n"}' 2>&1 | grep -avi memcache
kubectl -n "$ns" get subscriptions.sub.aitrustmt.msp "$nm" -o go-template='{{range $k,$v := .metadata.labels}}  L {{$k}}={{$v}}{{"\n"}}{{end}}{{range $k,$v := .metadata.annotations}}  A {{$k}}={{$v}}{{"\n"}}{{end}}' 2>&1 | grep -avi memcache | head -30

echo "=== 2. mirror namespace metadata (org/path?) ==="
kubectl get ns "$ns" -o go-template='{{range $k,$v := .metadata.labels}}  L {{$k}}={{$v}}{{"\n"}}{{end}}{{range $k,$v := .metadata.annotations}}  A {{$k}}={{$v}}{{"\n"}}{{end}}' 2>&1 | grep -avi memcache | head -20

echo "=== 3. syncagent PublishedResource — does it project labels/annotations/naming? ==="
kubectl get publishedresources.syncagent.kcp.io -A 2>&1 | grep -avi memcache | head
PR=$(kubectl get publishedresources.syncagent.kcp.io -A -o jsonpath='{.items[?(@.spec.resource.kind=="Subscription")].metadata.name}' 2>/dev/null | grep -avi memcache | awk '{print $1}')
echo "PR for Subscription: $PR"
kubectl get publishedresources.syncagent.kcp.io "$PR" -o jsonpath='{.spec}{"\n"}' 2>&1 | grep -avi memcache | head -40
echo DONE
