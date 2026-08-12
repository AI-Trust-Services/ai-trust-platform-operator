#!/bin/bash
# TASK A part 3b: strip ANSI, then read startup INF + any 'Adding certificate'/store lines.
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config 2>/dev/null
export KUBECONFIG="$STATE/shoot-kubeconfig.yaml"
G(){ grep -av memcache; }
STRIP(){ sed -E 's/\x1b\[[0-9;]*m//g'; }
POD="$(kubectl -n default get pods -l app.kubernetes.io/name=traefik -o jsonpath='{.items[0].metadata.name}' 2>/dev/null | G)"
echo "POD=$POD"
echo "### full first 40 startup lines (ANSI-stripped) ###"
kubectl -n default logs "$POD" 2>&1 | G | STRIP | head -40
echo
echo "### lines matching cert/tls/store/acme/alpn/default (ANSI-stripped, excl the HostRegexp spam) ###"
kubectl -n default logs "$POD" 2>&1 | G | STRIP | grep -iE 'cert|tls|store|acme|alpn|default|provider|entrypoint' | grep -viE 'No domain found in rule' | head -50
