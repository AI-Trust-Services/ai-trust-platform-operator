#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
TOK='eyJhbGciOiJSUzI1NiIsInR5cCIgOiAiSldUIiwia2lkIiA6ICJxTXlJZ000T253THRyRUlHLUI5SzJlaHJzZVFRUUVfVENIRzhjV1VMeHF3In0.eyJleHAiOjE3ODY0NzA1NzksImlhdCI6MTc4NjQ0MTc3OSwiYXV0aF90aW1lIjoxNzg2NDQxNzc4LCJqdGkiOiJiY2M3ZmFmOS05YmQ2LTRkZmMtMzA5MS1iY2I4MGI5MWMzOWQiLCJpc3MiOiJodHRwczovL2FpLXRydXN0LTEuYWktdHJ1c3Quc2hvb3QuZ2FyZGVuZXIuY2Mtb25lLnNob3dyb29tLmFwZWlyb3JhLmV1L2tleWNsb2FrL3JlYWxtcy9taXJjZWF0ZXN0MyIsImF1ZCI6ImI1ZWU1M2YwLWVhMzktNDU3Mi1hNTAzLTUxNmZlN2NhZTBkZSIsInN1YiI6ImNkNDIwNDQ5LTc4NGMtNDhmZi05MGM4LThjM2YwM2ZmYWVmOCIsInR5cCI6IklEIiwiYXpwIjoiYjVlZTUzZjAtZWEzOS00NTcyLWE1MDMtNTE2ZmU3Y2FlMGRlIiwic2lkIjoid1BWc0g4cVpGbnhLaWNIZEQwaUdjMmw2IiwiYXRfaGFzaCI6IlNVZlFDTURneExJeHR5Z0VodjdxTEEiLCJhY3IiOiIxIiwiZW1haWxfdmVyaWZpZWQiOmZhbHNlLCJuYW1lIjoibWlyY2VhIGNyYWNpdW4iLCJwcmVmZXJyZWRfdXNlcm5hbWUiOiJtaXJjZWEuY3JhY2l1bkBzYXAuY29tIiwiZ2l2ZW5fbmFtZSI6Im1pcmNlYSIsImZhbWlseV9uYW1lIjoiY3JhY2l1biIsImVtYWlsIjoibWlyY2VhLmNyYWNpdW5Ac2FwLmNvbSJ9.Z_du-8AkxNKu9YfqKrWgFZw5e5rb6v8uS0JpUdGfskyaybM4e6jWJw-UeGIRSIhoPnCFT351Rf3rixMts_7qEx1O2F9s14dns_ywOZYoef9HJt6sj3_0QK7f9Uzwk-oBWSqVVibKDS0LvlMOrcOsWK1FyteeH2GpHv0b-mLtC9h3WUvv9z-hloEl9fgA-TTKLq0vwdzXkzOZbyPi1bBqXLeeGH0e5-HlBTnBqxah4EJDu6Xsas_8RR761I0XsnsQxs62pI2A1E9S3A70TmSpRwBkdw9RK_h6pLcDxNpNXFJ4NV8oJIDdV_UVRYGnNWf9l5UXc0TpigLvqfnk4lAxmQ'
HOST=mirceatest3.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu
URL="https://$HOST/gateway/api/clusters/root:orgs:mirceatest3:accounttest/graphql"
# The v1alpha1 sub-type name follows the group: TrustAiTrustMspV1alpha1Mutation (guess) — introspect it.
for T in TrustAiTrustMspV1alpha1Mutation TrustAiTrustMspv1alpha1Mutation; do
echo "=== $T ==="
Q="{\"query\":\"query{__type(name:\\\"$T\\\"){fields{name args{name type{kind name ofType{kind name}}}}}}\"}"
sk -n platform-mesh-system run gv-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet -- \
  curl -sk -X POST "$URL" -H "Authorization: Bearer $TOK" -H 'Content-Type: application/json' --data "$Q" 2>/dev/null \
  | python3 -c "
import sys,json
d=json.load(sys.stdin)
t=(d.get('data') or {}).get('__type')
if not t: print('  (no such type)'); sys.exit()
for f in t.get('fields',[]):
    args=', '.join('%s:%s'%(a['name'],(a['type'].get('name') or (a['type'].get('ofType') or {}).get('name'))) for a in f.get('args',[]))
    print('  ',f['name'],'(',args,')')
" 2>&1 | head -30
done
