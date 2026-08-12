#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
echo "=== cloudprofiles (names only) ==="
garden get cloudprofile -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>&1 | grep -av memcache
echo "=== machine types in the FIRST cloudprofile, names only, grep large ==="
CP=$(garden get cloudprofile -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
echo "cp=$CP"
garden get cloudprofile "$CP" -o jsonpath='{range .spec.machineTypes[*]}{.name}{"|"}{.cpu}{"|"}{.memory}{"\n"}{end}' 2>&1 | grep -av memcache > "$STATE/mtypes.txt"
echo "total types: $(wc -l < "$STATE/mtypes.txt")"
echo "--- 16+ cpu options ---"
grep -E '^m_c16|^g_c16|^m_c32|^g_c32|c16_|c32_' "$STATE/mtypes.txt" | head -20
echo "--- anything with m128/m64/m32 ---"
grep -E 'm128|m64|m32' "$STATE/mtypes.txt" | head -20
