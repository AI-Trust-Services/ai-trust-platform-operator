#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
echo "=== shoot worker pools (name / type / min-max) ==="
garden get shoot "$SHOOT_NAME" -n "$PROJECT" -o jsonpath='{range .spec.provider.workers[*]}{.name}{" "}{.machine.type}{" min="}{.minimum}{" max="}{.maximum}{" zones="}{.zones}{"\n"}{end}' 2>&1 | grep -av memcache
echo "=== shoot lastOperation / any error ==="
garden get shoot "$SHOOT_NAME" -n "$PROJECT" -o jsonpath='{.status.lastOperation.state} {.status.lastOperation.description}{"\n"}' 2>&1 | grep -av memcache | head -c 300; echo
echo "=== machinedeployments (is msp-at-big scaling?) ==="
sk -n kube-system get nodes 2>&1 >/dev/null
garden get shoot "$SHOOT_NAME" -n "$PROJECT" -o jsonpath='{range .status.conditions[*]}{.type}={.status} {end}{"\n"}' 2>&1 | grep -av memcache
