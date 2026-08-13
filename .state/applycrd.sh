#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
echo "=== is the Subscription CRD installed on the SHOOT (where operator watches)? ==="
kubectl get crd subscriptions.sub.aitrustmt.msp -o jsonpath='{.spec.versions[0].schema.openAPIV3Schema.properties.spec.properties}{"\n"}' 2>&1 | grep -avi memcache | head -c 400; echo
echo
echo "=== apply the updated CRD (adds spec.org) to the shoot ==="
kubectl apply -f charts/aitrust-mt-app/crds/subscription.yaml 2>&1 | grep -avi memcache
echo "=== confirm org field now present ==="
kubectl get crd subscriptions.sub.aitrustmt.msp -o jsonpath='{.spec.versions[0].schema.openAPIV3Schema.properties.spec.properties.org}{"\n"}' 2>&1 | grep -avi memcache
echo DONE
