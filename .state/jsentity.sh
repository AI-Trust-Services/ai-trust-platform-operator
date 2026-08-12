#!/bin/bash
JS=/mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP/.state/wc.js
echo "=== context around .entity usage (create/mutation building) ==="
grep -oaE '.{80}create.{0,10}\.entity.{60}' "$JS" 2>/dev/null | head -3
grep -oaE '.{60}\.entity[^A-Za-z].{100}' "$JS" 2>/dev/null | head -6
echo "=== .apiGroup usage context ==="
grep -oaE '.{60}\.apiGroup[^A-Za-z].{80}' "$JS" 2>/dev/null | head -4
echo "=== .entityCollection usage context ==="
grep -oaE '.{40}\.entityCollection[^A-Za-z].{80}' "$JS" 2>/dev/null | head -3
echo "=== the mutation operation template (create + entity + Input) ==="
grep -oaE '.{40}\+"_Input.{40}' "$JS" 2>/dev/null | head -3
grep -oaE 'create.{0,4}concat.{0,40}' "$JS" 2>/dev/null | head -3
