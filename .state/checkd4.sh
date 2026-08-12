#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
echo "=== all pods in ns aitrust-msp ==="
sk -n aitrust-msp get pods --show-labels 2>/dev/null
echo ""
echo "=== deployments in ns aitrust-msp ==="
sk -n aitrust-msp get deploy 2>/dev/null
echo ""
echo "=== which pod backs svc aitrust-portal (endpoints) ==="
sk -n aitrust-msp get endpoints aitrust-portal -o wide 2>/dev/null
echo ""
echo "=== does the content pod see the new ConfigMap? mounted file group values ==="
POD=$(sk -n aitrust-msp get pods -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null | grep -i portal | head -1)
echo "content pod = $POD"
sk -n aitrust-msp exec "$POD" -- sh -c 'grep -ro "trust\.[a-z.-]*\.msp" /usr/share/nginx/html/pm-content.json 2>/dev/null; grep -ro "trust\.[a-z.-]*\.msp" /app 2>/dev/null; find / -name pm-content.json 2>/dev/null | head' 2>/dev/null | sort | uniq -c
