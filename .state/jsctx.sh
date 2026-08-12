#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
JS="$STATE/wc.js"
[ -s "$JS" ] || { echo "no wc.js"; exit 1; }
echo "=== context around create\${l} and \${i}\${t}_Input (how kind is derived) ==="
grep -oE '.{200}create\$\{l\}.{200}' "$JS" 2>/dev/null | head -3
echo "----"
grep -oE '.{260}\$\{i\}\$\{t\}_Input.{80}' "$JS" 2>/dev/null | head -3
echo "=== where do l/t/i come from? look for kind/version extraction near 'operationTemplate' ==="
grep -oE '.{300}operationTemplate.{300}' "$JS" 2>/dev/null | head -1
