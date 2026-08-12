#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
TOK='eyJhbGciOiJSUzI1NiIsInR5cCIgOiAiSldUIiwia2lkIiA6ICJldFBqYVBCZXQ4Z1Z5ZWV0QkY3a1BENVdtWWh5My1hS1ZJY0Y5NmlwUjRZIn0.eyJleHAiOjE3ODY0NzE3NTIsImlhdCI6MTc4NjQ0Mjk1MiwiYXV0aF90aW1lIjoxNzg2NDQyOTUxLCJqdGkiOiIzNWVkM2I0ZC1kMGNmLWMwZTItNjU3Yi0zYWU3MWY3MzJhNGQiLCJpc3MiOiJodHRwczovL2FpLXRydXN0LTEuYWktdHJ1c3Quc2hvb3QuZ2FyZGVuZXIuY2Mtb25lLnNob3dyb29tLmFwZWlyb3JhLmV1L2tleWNsb2FrL3JlYWxtcy9haXRydXN0ZnJlc2giLCJhdWQiOiJhZTM4YTgyYi04ODNlLTRmNzEtYTQ2MC1iOTY2NGYyYTM5NzUiLCJzdWIiOiJiZTQ2YzI1NS1lMjI1LTQ4ZWItOTQwYi01MjI0NjU0ZWI4YzYiLCJ0eXAiOiJJRCIsImF6cCI6ImFlMzhhODJiLTg4M2UtNGY3MS1hNDYwLWI5NjY0ZjJhMzk3NSIsInNpZCI6IjZQVWhIc3dmOXJBR2JUcFpVYTdCQUJZWSIsImF0X2hhc2giOiI2WkxVV1QxQ1VJZldaYnZ2Rm1fRHpnIiwiYWNyIjoiMSIsImVtYWlsX3ZlcmlmaWVkIjpmYWxzZSwibmFtZSI6Im1pcmNlYSBjcmFjaXVuIiwicHJlZmVycmVkX3VzZXJuYW1lIjoibWlyY2VhLmNyYWNpdW5Ac2FwLmNvbSIsImdpdmVuX25hbWUiOiJtaXJjZWEiLCJmYW1pbHlfbmFtZSI6ImNyYWNpdW4iLCJlbWFpbCI6Im1pcmNlYS5jcmFjaXVuQHNhcC5jb20ifQ.KSg5T2wxW5ZTOmoys77eKbPs5Eh6-gvNCmpwYwkXw16MbNpFK6zpvNqrHrxJx9U-4FazpUpWEZxNstE2fUtO0tTRSZa3QYKYN_9rAoPNyiFb1_Qh4k6niHk-Skennbmsq0z_ayBtdEPDpyvP61y3RVCJ7Q0LHfoQ-sdm3tl88GRJ_Q-zWeuHyJDFJztzD0fEsEUoHsRUK3PJ-JMarUwNIPD7AoQxkcS1MTDa3MD_95zDiOlVqx4yjp5kV2YOSaqwti98Ms9H3HCPzsN4dP5O2Q_Xe3Pg1gnxBxBndpK39f6Jkl6j-bFBMawrWaU5cLMZUudfCLfbbKbTNUtCX1F_DQ'
HOST=aitrustfresh.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu
URL="https://$HOST/gateway/api/clusters/root:orgs:aitrustfresh:demo/graphql"
echo "=== Query type fields (what the LIST view uses) — is there a trust_ai_trust_msp field? ==="
Q='{"query":"query{__schema{queryType{fields{name}}}}"}'
sk -n platform-mesh-system run q-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet -- \
  curl -sk -X POST "$URL" -H "Authorization: Bearer $TOK" -H 'Content-Type: application/json' --data "$Q" 2>/dev/null \
  | python3 -c "import sys,json;d=json.load(sys.stdin);print([f['name'] for f in ((d.get('data') or {}).get('__schema') or {}).get('queryType',{}).get('fields',[]) if 'trust' in f['name'].lower() or 'v1alpha1' in f['name'].lower()])"
