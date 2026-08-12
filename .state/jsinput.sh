#!/bin/bash
JS=/mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP/.state/wc.js
echo "=== the full _Input builder function (around dm) ==="
grep -oaE '.{140}return`\$\{i\}\$\{t\}_Input`.{20}' "$JS" 2>/dev/null | head -2
echo "=== find the function that computes i and t (the _Input prefix) ==="
grep -oaE 'function [a-zA-Z0-9]{1,4}\([^)]*\)\{[^}]{0,120}_Input`\}' "$JS" 2>/dev/null | head -3
echo "=== the create operation: top field + create<entity> ==="
grep -oaE '.{100}operation:[^,]{0,40}create.{0,60}' "$JS" 2>/dev/null | head -4
echo "=== how apiGroup is normalized to a GraphQL field (replace . and -) ==="
grep -oaE '[a-zA-Z]{1,20}\.replace\(/\[?\.?-?\]?/[a-z]*,.{0,10}\)' "$JS" 2>/dev/null | sort -u | head
grep -oaE 'replace\(/\[\.\\?-\]/g,"_"\)' "$JS" 2>/dev/null | head
