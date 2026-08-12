#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
python3 <<'PY'
import json
pll=json.load(open('.state/pll-content.json'))
n=pll['luigiConfigFragment']['data']['nodes'][0]
rd=n['context']['resourceDefinition']
print("=== WORKING private-llm resourceDefinition (full, minus ui) ===")
print(json.dumps({k:v for k,v in rd.items() if k!='ui'}, indent=2))
print("=== does it have a top-level 'kind' AND anything the mutation-builder keys on? ===")
print("keys:", list(rd.keys()))
# also dump how many nodes + the create child structure
print("=== node has children? ===", 'children' in n)
PY
