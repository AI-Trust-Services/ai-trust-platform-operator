#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
echo "=== does the gardener Certificate 'domain-certificate' write the SECRET 'domain-certificate'? ==="
kubectl -n platform-mesh-system get certificate.cert.gardener.cloud domain-certificate -o jsonpath='dnsNames={.spec.dnsNames}{"\n"}secretRef={.spec.secretRef}{"\n"}secretName={.spec.secretName}{"\n"}state={.status.state}{"\n"}' 2>&1 | grep -av memcache
echo "=== the secret's current annotations — is it managed by a gardener Certificate now? ==="
kubectl -n platform-mesh-system get secret domain-certificate -o jsonpath='{range .metadata.ownerReferences[*]}owner={.kind}/{.name}{"\n"}{end}annos={.metadata.annotations}{"\n"}' 2>&1 | grep -av memcache | head -c 500; echo
echo "=== what SANs does the gardener 'domain-certificate' Certificate cover? (if it renews, does it cover our hosts?) ==="
kubectl -n platform-mesh-system get certificate.cert.gardener.cloud domain-certificate -o jsonpath='{.status.dnsNames}{"\n"}' 2>&1 | grep -av memcache
