#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
echo "=== ALL LoadBalancer svcs (find the gateway one) ==="
sk -A get svc -o wide 2>&1 | grep -av memcache | awk 'NR==1 || /LoadBalancer/'
echo "=== ALL deployments whose name or image hints traefik (broad) ==="
sk -A get deploy 2>&1 | grep -av memcache | grep -iE 'traefik'
sk -A get deploy -o wide 2>&1 | grep -av memcache | grep -iE 'traefik' | head
echo "=== if none by name, find by image ==="
sk -A get pods -o jsonpath='{range .items[*]}{.metadata.namespace}{" "}{.metadata.name}{" "}{.spec.containers[*].image}{"\n"}{end}' 2>&1 | grep -av memcache | grep -iE 'traefik' | head
