#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
JS="$STATE/wc.js"
[ -s "$JS" ] || { echo "no wc.js ($(ls -la "$STATE"/wc.js 2>&1))"; exit 1; }
echo "size=$(wc -c < "$JS")"
# The broken query used: create${l}, and top field was the version. Find the exact builder.
# Search for the literal template pieces that survive minification.
echo "=== occurrences of createundefined-style template: 'create'+var concatenation ==="
grep -oaE '"create"\+[a-zA-Z0-9_$.]{1,30}' "$JS" | sort -u | head
grep -oaE 'create[`"]?\+[a-zA-Z0-9_$.]{1,20}' "$JS" | sort -u | head
echo "=== _Input concatenation ==="
grep -oaE '[a-zA-Z0-9_$.]{1,20}\+[`"]?_Input' "$JS" | sort -u | head
grep -oaE '[a-zA-Z0-9_$.]{1,25}\+"_Input"' "$JS" | sort -u | head
echo "=== which property does it read: .kind vs .entity vs .entityKind — counts ==="
for p in '\.kind' '\.entity' '\.entityKind' '\.apiGroup' '\.group' '\.plural' '\.entityCollection' '\.singular'; do
  printf "%-18s %s\n" "$p" "$(grep -oaE "$p[^A-Za-z]" "$JS" 2>/dev/null | wc -l)"
done
