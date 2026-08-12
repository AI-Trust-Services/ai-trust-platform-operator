#!/bin/bash
# TASK A part 2 (READ-ONLY): query the RUNNING traefik API (rawdata + tls) to see which certs it
# actually loaded and how routers map to them. No changes; only in-cluster GET via kubectl exec-less
# ephemeral curl pod against the traefik ClusterIP:8080 (api/dashboard entrypoint).
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config 2>/dev/null
export KUBECONFIG="$STATE/shoot-kubeconfig.yaml"
G(){ grep -av memcache; }
SUF=ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu
LB=130.214.18.166

echo "### traefik ClusterIP + pod IP (api on :8080, websecure on :8443) ###"
TCIP="$(kubectl -n default get svc traefik -o jsonpath='{.spec.clusterIP}' 2>/dev/null | G)"
POD="$(kubectl -n default get pods -l app.kubernetes.io/name=traefik -o jsonpath='{.items[0].metadata.name}' 2>/dev/null | G)"
PIP="$(kubectl -n default get pod "$POD" -o jsonpath='{.status.podIP}' 2>/dev/null | G)"
echo "svcClusterIP=$TCIP podIP=$PIP pod=$POD"
echo

echo "### rawdata: routers on websecure + their TLS. Look for whether routers carry a tls domain or not ###"
kubectl -n default run rawq-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet -- \
  sh -c "curl -s http://$PIP:8080/api/rawdata" 2>&1 | G > "$STATE/taskA-rawdata.json"
echo "bytes: $(wc -c < "$STATE/taskA-rawdata.json" 2>/dev/null)"
echo

echo "### does rawdata mention any tls certificates block / defaultCertificate / stores? ###"
grep -oiE '"(tls|certificates|defaultCertificate|stores|options)"' "$STATE/taskA-rawdata.json" 2>/dev/null | sort | uniq -c | G
echo

echo "### live served cert for a real instance host (in-cluster, SNI = my-aitrust.<suf>) ###"
kubectl -n default run tlsq-$RANDOM --rm -i --restart=Never --image=alpine/openssl:latest --quiet -- \
  sh -c "echo | openssl s_client -connect $LB:443 -servername my-aitrust.$SUF 2>/dev/null | openssl x509 -noout -subject -issuer -dates" 2>&1 | G
echo
echo "### and for the apex host + a services host, for completeness ###"
kubectl -n default run tlsq2-$RANDOM --rm -i --restart=Never --image=alpine/openssl:latest --quiet -- \
  sh -c "echo | openssl s_client -connect $LB:443 -servername $SUF 2>/dev/null | openssl x509 -noout -subject -issuer" 2>&1 | G
