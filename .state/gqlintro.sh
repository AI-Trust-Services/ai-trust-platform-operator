#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
# The portal reaches the gateway at /gateway/api/clusters/root:orgs:<org>/graphql (per portal env).
# Introspect the mutation type names for the consumer account to see if AITrust builds cleanly.
HOST=mirceatest3.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu
Q='{"query":"query{__type(name:\"Mutation\"){fields{name}}}"}'
echo "=== introspect Mutation fields via the gateway (through the portal host) ==="
sk -n platform-mesh-system run gqli-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet -- \
  curl -sk -X POST "https://$HOST/gateway/api/clusters/root:orgs:mirceatest3:accounttest/graphql" \
  -H 'Content-Type: application/json' --data "$Q" 2>/dev/null > "$STATE/gqlintro.json"
head -c 400 "$STATE/gqlintro.json"; echo
echo "=== grep for trust_ai / aitrust / undefined in the schema ==="
grep -oiE 'trust[_a-z]*|aitrust[a-z]*|undefined' "$STATE/gqlintro.json" 2>/dev/null | sort -u | head
