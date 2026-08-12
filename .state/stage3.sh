#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
GW=k8sapi-gateway; NS=platform-mesh-system
echo "=== find terminate-wildstar listener index ==="
IDX=$(sk -n "$NS" get gateway "$GW" -o json 2>/dev/null | python3 -c "import json,sys;l=json.load(sys.stdin)['spec']['listeners'];print(next((i for i,x in enumerate(l) if x['name']=='terminate-wildstar'),-1))")
echo "terminate-wildstar index=$IDX (certRef before: $(sk -n "$NS" get gateway "$GW" -o jsonpath="{.spec.listeners[$IDX].tls.certificateRefs[0].name}" 2>/dev/null))"
[ "$IDX" -ge 0 ] 2>/dev/null || { echo "NOT FOUND — abort"; exit 1; }
echo "=== REPOINT terminate-wildstar certRef -> cert-p1 ==="
sk -n "$NS" patch gateway "$GW" --type=json -p "[{\"op\":\"replace\",\"path\":\"/spec/listeners/$IDX/tls/certificateRefs/0/name\",\"value\":\"cert-p1\"}]" 2>&1 | grep -av memcache
echo "=== SAFETY WATCH: Programmed must stay True on ALL listeners ==="
for i in 1 2 3 4 5 6; do
  sk -n "$NS" get gateway "$GW" -o jsonpath='Programmed={.status.conditions[?(@.type=="Programmed")].status}  wildstar={range .status.listeners[?(@.name=="terminate-wildstar")]}{.conditions[?(@.type=="Programmed")].status}/{.conditions[?(@.type=="ResolvedRefs")].status}{end}{"\n"}' 2>&1 | grep -av memcache
  sleep 4
done
echo "=== VERIFY: instance hosts now serve Lets Encrypt; portal/apex still self-signed (unchanged) ==="
LB=130.214.18.166
iss(){ sk -n "$NS" run x-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet -- sh -c "echo Q | openssl s_client -connect $LB:443 -servername $1 2>/dev/null | openssl x509 -noout -issuer" 2>&1 | grep -aiE 'issuer'; }
echo -n "d (instance, wildstar): "; iss 25veqwflh7syq7fm-d.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu
echo -n "testai (instance, wildstar): "; iss testai.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu
echo -n "apex (terminate, untouched): "; iss ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu
