#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
echo "=== working private-llm syncagent ARGS + env + volumeMounts ==="
sk -n private-llm get deploy private-llm -o jsonpath='{range .spec.template.spec.containers[*]}{.name}{": args="}{.args}{" cmd="}{.command}{"\n"}{end}' 2>&1 | grep -av memcache
echo "--- full container spec (the api-syncagent one) ---"
sk -n private-llm get deploy private-llm -o yaml 2>&1 | grep -av memcache | sed -n '/api-syncagent/,/volumeMounts/p' | head -40
echo "=== how the chart wires kubeconfig: secrets + volumes ==="
sk -n private-llm get deploy private-llm -o jsonpath='{.spec.template.spec.volumes}{"\n"}' 2>&1 | grep -av memcache
