#!/bin/bash
exec > /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP/.state/step5-durab.out 2>&1
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
[ -s "$SHOOT_KUBECONFIG" ] || mint_shoot_kubeconfig || { echo LOGIN_EXPIRED; exit 3; }
GWNS=platform-mesh-system

echo "############ 1. Is domain-certificate-ca produced by a cert-manager/gardener Certificate, or hand-applied? ############"
echo "-- ownerRefs / managed-by / last-applied on domain-certificate-ca --"
kubectl -n "$GWNS" get secret domain-certificate-ca -o jsonpath='ownerRefs={.metadata.ownerReferences} labels={.metadata.labels}{"\n"}annos={.metadata.annotations}{"\n"}' 2>&1 | grep -avi memcache | tr ',' '\n' | grep -iE 'owner|managed-by|helm|flux|cert-manager|last-applied|kind' | head
echo "-- any cert-manager Certificate or gardener Certificate that WRITES domain-certificate-ca? --"
kubectl -n "$GWNS" get certificate.cert-manager.io -o custom-columns='NAME:.metadata.name,SECRET:.spec.secretName' 2>&1 | grep -avi memcache | grep -iE 'domain-certificate-ca|NAME' || echo "  (no cert-manager cert -> domain-certificate-ca)"
kubectl -n "$GWNS" get certificate.cert.gardener.cloud -o custom-columns='NAME:.metadata.name,SECRET:.spec.secretRef.name' 2>&1 | grep -avi memcache | grep -iE 'domain-certificate-ca|NAME' || echo "  (no gardener cert -> domain-certificate-ca)"

echo
echo "############ 2. Is domain-certificate (served) produced by a Certificate, or hand-applied? ############"
kubectl -n "$GWNS" get secret domain-certificate -o jsonpath='ownerRefs={.metadata.ownerReferences} managed-by={.metadata.labels.app\.kubernetes\.io/managed-by}{"\n"}' 2>&1 | grep -avi memcache
kubectl -n "$GWNS" get certificate.cert-manager.io -o custom-columns='NAME:.metadata.name,SECRET:.spec.secretName' 2>&1 | grep -avi memcache | grep -iE 'domain-certificate$|domain-certificate ' || echo "  (no cert-manager cert -> domain-certificate)"
kubectl -n "$GWNS" get certificate.cert.gardener.cloud domain-certificate -o jsonpath='gardenerCert domain-certificate secret={.spec.secretRef.name} state={.status.state}{"\n"}' 2>&1 | grep -avi memcache || echo "  (no gardener cert named domain-certificate)"

echo
echo "############ 3. infra HelmRelease: source (git repo we could PR) + does it template these secrets? ############"
kubectl -n "$GWNS" get helmrelease infra -o jsonpath='chart={.spec.chart.spec.chart} sourceKind={.spec.chart.spec.sourceRef.kind} sourceName={.spec.chart.spec.sourceRef.name} interval={.spec.interval}{"\n"}' 2>&1 | grep -avi memcache
echo "-- the source object (where the chart values live) --"
kubectl -n "$GWNS" get helmrelease infra -o jsonpath='{.spec.chart.spec.sourceRef.kind}/{.spec.chart.spec.sourceRef.name}' 2>&1 | grep -avi memcache
SRCK=$(kubectl -n "$GWNS" get helmrelease infra -o jsonpath='{.spec.chart.spec.sourceRef.kind}' 2>/dev/null)
SRCN=$(kubectl -n "$GWNS" get helmrelease infra -o jsonpath='{.spec.chart.spec.sourceRef.name}' 2>/dev/null)
SRCNS=$(kubectl -n "$GWNS" get helmrelease infra -o jsonpath='{.spec.chart.spec.sourceRef.namespace}' 2>/dev/null); SRCNS=${SRCNS:-$GWNS}
echo; echo "-- source detail ($SRCK/$SRCN in $SRCNS) --"
kubectl -n "$SRCNS" get "$SRCK" "$SRCN" -o jsonpath='url={.spec.url} ref={.spec.ref}{"\n"}' 2>&1 | grep -avi memcache | head

echo
echo "############ 4. VERDICT on durability risk ############"
echo "  - If domain-certificate-ca has NO cert-manager/gardener Certificate producing it (hand-applied), then Flux"
echo "    reconciling 'infra' will NOT overwrite its DATA (infra only references it by name via caSecret). => stable."
echo "  - If a Certificate DOES produce it, that Certificate is the durable knob."
echo DONE
