#!/bin/bash
# TASK B tiebreaker — the plain probe said "TRAEFIK DEFAULT CERT", -showcerts said "ai-trust-1-mesh".
# Resolve it: for each SNI/port, print the LEAF (first cert in -showcerts) subject+issuer authoritatively.
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=platform-mesh-system; LB=130.214.18.166; SUF="$INSTANCE_DOMAIN_SUFFIX"

kubectl -n "$NS" run tbtie-$RANDOM --rm -i --restart=Never --image=alpine/openssl:latest --quiet \
  --env="SUF=$SUF" --command -- sh -c '
leaf() {
  port="$1"; sni="$2"
  # -showcerts, take ONLY the first BEGIN..END block = the leaf actually presented for this SNI
  block=$(echo | openssl s_client -connect 130.214.18.166:${port} -servername "${sni}" -showcerts 2>/dev/null \
    | awk "/BEGIN CERT/{n++} n==1{print} /END CERT/{if(n==1) exit}")
  if [ -z "$block" ]; then echo "  [$port] $sni -> NO LEAF"; return; fi
  info=$(echo "$block" | openssl x509 -noout -subject -issuer 2>/dev/null)
  s=$(echo "$info" | sed -n "s/^subject=//p"); i=$(echo "$info" | sed -n "s/^issuer=//p")
  echo "  [$port] $sni"
  echo "        leaf subject: $s"
  echo "        leaf issuer : $i"
}
for P in 443 8443; do
  echo "===== PORT $P ====="
  leaf $P "testai.$SUF"
  leaf $P "25veqwflh7syq7fm-d.$SUF"
  leaf $P "portal.$SUF"
  leaf $P "$SUF"
  leaf $P "foo.services.$SUF"
  leaf $P "nope-$RANDOM.$SUF"
done
' 2>&1 | grep -av memcache
