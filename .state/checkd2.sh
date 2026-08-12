#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
echo "=== portal pods in aitrust-msp ==="
sk -n aitrust-msp get pods -o wide 2>/dev/null
echo "=== configmaps in aitrust-msp (names) ==="
sk -n aitrust-msp get cm -o name 2>/dev/null
echo "=== grep served content for group string across fresh fetch ==="
sk -n platform-mesh-system run cdx-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet -- \
  curl -sS http://aitrust-portal.aitrust-msp.svc.cluster.local/pm-content.json 2>/dev/null | tr ',' '\n' | grep -i 'group\|trust'
