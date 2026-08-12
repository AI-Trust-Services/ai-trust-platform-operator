#!/bin/bash
F=/mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP/prerequisites/config.env
echo "=== file ==="
file "$F"
echo "=== CR check ==="
if grep -qU $'\r' "$F"; then echo "YES_CRLF"; else echo "LF_ONLY"; fi
echo "=== first 60 bytes od ==="
head -c 60 "$F" | od -c | head -4
echo "=== does a direct source populate SHOOT_NAME? ==="
set -a; source "$F"; set +a
echo "SHOOT_NAME=[$SHOOT_NAME] PROVIDER_WS=[$PROVIDER_WS]"
