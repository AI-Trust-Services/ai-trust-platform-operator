#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh
load_config
echo "=== working private-llm syncagent image (from the live deploy) ==="
sk -n private-llm get deploy -o jsonpath='{range .items[*]}{.metadata.name}{" -> "}{.spec.template.spec.containers[*].image}{"\n"}{end}' 2>&1 | grep -av memcache | grep -i syncagent
echo "=== all container images in private-llm (find the api-syncagent one) ==="
sk -n private-llm get pods -o jsonpath='{range .items[*]}{range .spec.containers[*]}{.image}{"\n"}{end}{end}' 2>&1 | grep -av memcache | grep -i syncagent | sort -u
