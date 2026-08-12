#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
echo "=== restart the content nginx so it serves the corrected pm-content.json ==="
sk -n "$PROVIDER_NS" rollout restart deployment/aitrust-portal-integration 2>&1 | grep -av memcache
sk -n "$PROVIDER_NS" rollout status deployment/aitrust-portal-integration --timeout=120s 2>&1 | grep -av memcache | tail -1
sleep 5
echo "=== re-verify served group (expect trust.aitrust.msp, NOT hyphenated) ==="
for i in 1 2 3; do
  sk -n platform-mesh-system run cd-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet -- \
    curl -sS http://aitrust-portal.aitrust-msp.svc.cluster.local/pm-content.json 2>/dev/null > "$STATE/served.json"
  [ -s "$STATE/served.json" ] && break; sleep 3
done
python3 -c "
import json
d=json.load(open('$STATE/served.json'))
rd=d['luigiConfigFragment']['data']['nodes'][0]['context']['resourceDefinition']
print('served group =', rd.get('group'))
print('hyphenated occurrences:', open('$STATE/served.json').read().count('trust.ai-trust.msp'))
print('new-group occurrences:', open('$STATE/served.json').read().count('trust.aitrust.msp'))
"
