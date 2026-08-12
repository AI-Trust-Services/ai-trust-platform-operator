#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
JS="$STATE/wc.js"
echo "=== template: create + version + _Input (find the function that builds it) ==="
grep -oaE '.{160}create\$\{[a-zA-Z]\}\(namespace.{120}' "$JS" 2>/dev/null | head -2
echo "----- input type template -----"
grep -oaE '.{200}_Input.{20}' "$JS" 2>/dev/null | grep -aE 'mutation|\$\{' | head -3
echo "=== find how kind is computed — look for 'kind' near capitalize/pascal + resourceDefinition ==="
grep -oaE '.{80}[Cc]apitalize.{0,40}kind.{80}' "$JS" 2>/dev/null | head -3
grep -oaE 'resourceDefinition[.\[][a-zA-Z"]{0,20}' "$JS" 2>/dev/null | sort -u | head -20
echo "=== does the create builder read spec.crd / crdName / .kind from context? ==="
grep -oaE '.{60}\.kind[^A-Za-z].{60}' "$JS" 2>/dev/null | grep -aiE 'toUpper|pascal|capital|charAt|slice|undefined|resourceDef' | head -5
