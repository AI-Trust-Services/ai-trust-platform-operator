#!/bin/bash
# TASK D — supplemental READ-ONLY: distinguish gardener cert/dns CRs from cert-manager, record CRDs.
set +e
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP || exit 1
source scripts/lib.sh
load_config
BK="$STATE/backup-dnscert"; mkdir -p "$BK"
TO=/usr/bin/timeout
SKC="$SHOOT_KUBECONFIG"

echo "===== relevant CRDs present ====="
$TO 25 kubectl --kubeconfig "$SKC" get crd </dev/null 2>&1 | grep -iE 'dns.gardener.cloud|cert.gardener.cloud|cert-manager.io' | head

echo; echo "===== GARDENER cert.gardener.cloud Certificates (all ns) ====="
$TO 25 kubectl --kubeconfig "$SKC" get certificates.cert.gardener.cloud -A </dev/null 2>&1 | head
echo "-> saving to gardener-certificates.yaml"
$TO 25 kubectl --kubeconfig "$SKC" get certificates.cert.gardener.cloud -A -o yaml </dev/null > "$BK/gardener-certificates.yaml" 2>&1
echo "bytes=$(wc -c < "$BK/gardener-certificates.yaml")"

echo; echo "===== GARDENER dns.gardener.cloud DNSEntries (all ns) ====="
$TO 25 kubectl --kubeconfig "$SKC" get dnsentries.dns.gardener.cloud -A </dev/null 2>&1 | head
echo; echo "===== GARDENER DNSProviders (all ns) ====="
$TO 25 kubectl --kubeconfig "$SKC" get dnsproviders.dns.gardener.cloud -A </dev/null 2>&1 | head

echo; echo "===== domain-certificate secret identity (type + keys + annotations; NO bytes) ====="
$TO 25 kubectl --kubeconfig "$SKC" -n "$GATEWAY_NS" get secret domain-certificate \
  -o jsonpath='{.type}{"\n"}annotations={.metadata.annotations}{"\n"}labels={.metadata.labels}{"\n"}keys={.data}{"\n"}' </dev/null 2>&1 \
  | sed -E 's/(tls.crt|tls.key|ca.crt):[A-Za-z0-9+/=]+/\1:<REDACTED>/g' | head -8

echo; echo "===== gateway: which listeners ref domain-certificate ====="
$TO 25 kubectl --kubeconfig "$SKC" -n "$GATEWAY_NS" get gateway "$GATEWAY_NAME" \
  -o jsonpath='{range .spec.listeners[*]}{.name}{" host="}{.hostname}{" certRefs="}{.tls.certificateRefs[*].name}{"\n"}{end}' </dev/null 2>&1
