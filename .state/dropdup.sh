#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
OLD=aitp-33hins0iklcwfg45-d
echo "=== why does the OLD copy exist? check for a mirrored CR in that logical cluster ==="
setup_kcp >/dev/null 2>&1; kcp_portforward >/dev/null 2>&1
for i in $(seq 1 10); do kc root get workspace >/dev/null 2>&1 && break; sleep 2; done
sk get aitrustplatforminstance -A 2>&1 | grep -av memcache | grep -E 'NAMESPACE|33hins|25veqw'
echo "=== remove the OLD duplicate: its gateway routes + its namespace ==="
sk -n "$GATEWAY_NS" delete httproute aitp-33hins0iklcwfg45-d-app aitp-33hins0iklcwfg45-d-keycloak --ignore-not-found 2>&1 | grep -av memcache
# remove any mirrored CR in the 33hins cluster so the operator won't re-stamp it
sk -n 33hins0iklcwfg45 delete aitrustplatforminstance d --ignore-not-found 2>&1 | grep -av memcache
sk delete ns "$OLD" --wait=false 2>&1 | grep -av memcache
echo "=== confirm only the good copy + host remain ==="
sleep 5
sk get ns 2>&1 | grep -av memcache | grep -E 'aitp.*-d'
sk -n "$GATEWAY_NS" get httproute 2>&1 | grep -av memcache | grep -E '\-d-app|\-d-keycloak'
