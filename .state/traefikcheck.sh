#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
NS=platform-mesh-system; LB=130.214.18.166
echo "=== confirm the spec change is really there ==="
sk -n "$NS" get gateway k8sapi-gateway -o jsonpath='{range .spec.listeners[?(@.name=="terminate-wildstar")]}wildstar certRef={.tls.certificateRefs[0].name} ns={.tls.certificateRefs[0].namespace}{"\n"}{end}' 2>&1 | grep -av memcache
echo "=== where does Traefik run + does it see cert-p1? (traefik reads the Gateway) ==="
sk -A get pods 2>&1 | grep -av memcache | grep -iE 'traefik' | head
echo "=== give Traefik ~30s to reload, then re-probe testai issuer ==="
sleep 30
sk -n "$NS" run r-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet -- \
  curl -kv --resolve testai.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu:443:$LB https://testai.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu/ 2>&1 | grep -av memcache | grep -iE 'issuer:|subject:' | head
echo "=== is cert-p1 secret actually of type kubernetes.io/tls with tls.crt+tls.key? (traefik needs both) ==="
sk -n "$NS" get secret cert-p1 -o jsonpath='type={.type} hasCrt={.data.tls\.crt} hasKey={.data.tls\.key}{"\n"}' 2>&1 | grep -av memcache | sed 's/\(hasCrt=\)[A-Za-z0-9+/=]\{20\}[A-Za-z0-9+/=]*/\1<present>/; s/\(hasKey=\)[A-Za-z0-9+/=]\{20\}[A-Za-z0-9+/=]*/\1<present>/'
