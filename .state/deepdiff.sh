#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
python3 <<'PY'
import json
mine=json.load(open(".state/mine-content.json"))
pll=json.load(open(".state/pll-content.json"))
mrd=mine["luigiConfigFragment"]["data"]["nodes"][0]["context"]["resourceDefinition"]
prd=pll["luigiConfigFragment"]["data"]["nodes"][0]["context"]["resourceDefinition"]
print("=== WORKING resourceDefinition (values) ===")
for k in ["group","version","plural","singular","kind","scope"]:
    print(f"  {k} = {prd.get(k)!r}")
print("=== MINE resourceDefinition (values) ===")
for k in ["group","version","plural","singular","kind","scope"]:
    print(f"  {k} = {mrd.get(k)!r}")
print()
# The GraphQL type is TrustAiTrustMspV1alpha1<Kind>_Input. The portal query builder likely computes
# the group->field. Working: llm.privatellms.msp -> ??? . Let's see what top mutation field the portal
# would derive. The gateway uses group with dots->_ : trust_ai_trust_msp. But portal used 'v1alpha1'.
# Compare the WORKING child graphqlEntity vs mine (create may read kind from there via defineEntity).
mc=mine["luigiConfigFragment"]["data"]["nodes"][0].get("children",[])
pc=pll["luigiConfigFragment"]["data"]["nodes"][0].get("children",[])
print("=== WORKING child[0] full ===")
print(json.dumps(pc[0], indent=2)[:700] if pc else "(none)")
print("=== MINE child[0] full ===")
print(json.dumps(mc[0], indent=2)[:700] if mc else "(none)")
PY
