#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
echo "=== ROLLBACK: repoint terminate-wildstar certRef back to domain-certificate (baseline) ==="
IDX=$(kubectl -n platform-mesh-system get gateway k8sapi-gateway -o json 2>/dev/null | python3 -c "import json,sys;l=json.load(sys.stdin)['spec']['listeners'];print(next((i for i,x in enumerate(l) if x['name']=='terminate-wildstar'),-1))")
kubectl -n platform-mesh-system patch gateway k8sapi-gateway --type=json -p "[{\"op\":\"replace\",\"path\":\"/spec/listeners/$IDX/tls/certificateRefs/0/name\",\"value\":\"domain-certificate\"}]" 2>&1 | grep -av memcache
echo "=== confirm restored + Programmed ==="
kubectl -n platform-mesh-system get gateway k8sapi-gateway -o jsonpath='wildstar certRef={.spec.listeners['$IDX'].tls.certificateRefs[0].name} Programmed={.status.conditions[?(@.type=="Programmed")].status}{"\n"}' 2>&1 | grep -av memcache
echo "=== WHY it didn't work: check Traefik default TLS store / TLSOption / default cert ==="
kubectl get tlsstores.traefik.io -A 2>&1 | grep -av memcache | head
kubectl -n default get deploy traefik -o jsonpath='{range .spec.template.spec.containers[0].args[*]}{@}{"\n"}{end}' 2>&1 | grep -av memcache | grep -iE 'default|tls|certificate|gateway' | head
