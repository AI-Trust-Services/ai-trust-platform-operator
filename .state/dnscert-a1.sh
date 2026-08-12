#!/bin/bash
# TASK A probe #1 — reachability + DNS/cert CRDs + existing objects (READ-ONLY)
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh
load_config
BK=".state/backup-dnscert"
mkdir -p "$BK"

echo "===================================================================="
echo "STEP 0: shoot reachability (mint kubeconfig / cluster-info)"
echo "===================================================================="
# Try to reach shoot. If mint hangs on OIDC, we time it out and report.
timeout 60 bash -c '
  source scripts/lib.sh; load_config
  sk version --short 2>&1 | head -5
' 2>&1
RC=$?
if [ $RC -ne 0 ]; then
  echo "SHOOT_UNREACHABLE rc=$RC (likely garden login expired — needs prerequisites/login.sh)"
fi

echo
echo "===================================================================="
echo "STEP 1: DNS/cert CRDs present on the shoot?"
echo "===================================================================="
timeout 60 bash -c '
  source scripts/lib.sh; load_config
  sk get crd 2>&1 | grep -iE "dns.gardener.cloud|cert.gardener.cloud" || echo "NO_DNS_CERT_CRDS_FOUND"
' 2>&1
