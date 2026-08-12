#!/bin/bash
# TASK A part 3 (STRICT READ-ONLY): full startup INF sequence + how the listener certRef becomes a cert.
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config 2>/dev/null
export KUBECONFIG="$STATE/shoot-kubeconfig.yaml"
G(){ grep -av memcache; }
POD="$(kubectl -n default get pods -l app.kubernetes.io/name=traefik -o jsonpath='{.items[0].metadata.name}' 2>/dev/null | G)"
echo "POD=$POD"
echo

echo "### 1. ALL INF lines (startup config summary — providers, entrypoints, tls-alpn) ###"
kubectl -n default logs "$POD" 2>&1 | G | grep -E '\bINF\b' | head -60
echo

echo "### 2. Any line mentioning the served cert secret names (domain-certificate / cert-p1) ? ###"
kubectl -n default logs "$POD" 2>&1 | G | grep -iE 'domain-certificate|cert-p1|certificate' | grep -viE 'No domain found' | head -30
echo

echo "### 3. Distinct router rule shapes actually built (Host vs HostRegexp vs HostSNI) ###"
kubectl -n default logs "$POD" 2>&1 | G | grep -oE 'HostRegexp\([^)]*\)|HostSNI\([^)]*\)|(^| )Host\([^)]*\)' | sed -E 's/\("[^"]*".*/(...)/' | sort | uniq -c | G
echo

echo "### 4. Confirm no non-regex Host router for instance/apex (search rendered rules for literal my-aitrust) ###"
kubectl -n default logs "$POD" 2>&1 | G | grep -iE 'my-aitrust|testai' | grep -oE 'Host[A-Za-z]*\(' | sort | uniq -c | G
echo "(expect only HostRegexp( — proving concrete-host routes are regex-compiled, so no per-host cert bind)"
