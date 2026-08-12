#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
echo "=== testai namespace + host ==="
sk get ns 2>&1 | grep -av memcache | grep -E 'aitp.*testai'
echo "=== testai HTTPRoutes on the gateway (name + host + current sectionName) ==="
for r in $(sk -n platform-mesh-system get httproute -o name 2>/dev/null | grep -i testai); do
  echo "$r  host=$(sk -n platform-mesh-system get "$r" -o jsonpath='{.spec.hostnames[0]}' 2>/dev/null)  section=$(sk -n platform-mesh-system get "$r" -o jsonpath='{.spec.parentRefs[0].sectionName}' 2>/dev/null)"
done
echo "=== testai instance status.url (the exact host to serve) ==="
setup_kcp >/dev/null 2>&1; kcp_portforward >/dev/null 2>&1
for i in $(seq 1 12); do kc root get workspace >/dev/null 2>&1 && break; sleep 2; done
trap 'pkill -f "port-forward.*root-proxy.*6443" 2>/dev/null||true' EXIT
for WS in root:orgs:aitrustg2:demo root:orgs:mirceatest3:accounttest; do
  kc "$WS" -n default get aitrustplatforminstance testai -o jsonpath="$WS: url={.status.url} ns={.status.namespace}{\"\n\"}" 2>/dev/null | grep -av memcache
done
echo "=== baseline: what cert does testai serve today (should be self-signed) ==="
HOST=$(sk -n platform-mesh-system get httproute -o jsonpath='{range .items[*]}{.spec.hostnames[0]}{"\n"}{end}' 2>/dev/null | grep -av memcache | grep -i testai | head -1)
echo "testai host = $HOST"
[ -n "$HOST" ] && sk -n platform-mesh-system run tb-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet -- \
  sh -c "echo | openssl s_client -connect 130.214.18.166:443 -servername $HOST 2>/dev/null | openssl x509 -noout -issuer 2>/dev/null" 2>&1 | grep -av memcache
