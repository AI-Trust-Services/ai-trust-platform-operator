#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
[ -s "$SHOOT_KUBECONFIG" ] || mint_shoot_kubeconfig >/dev/null 2>&1
export KUBECONFIG="$SHOOT_KUBECONFIG"
echo "=== A) API reachable right now? ==="
kubectl get --raw='/healthz' 2>&1 | grep -av memcache | head -1
echo "=== B) testai pods (1 line) ==="
kubectl -n aitp-33hins0iklcwfg45-testai get deploy oauth2-proxy shell -o jsonpath='oauth2={.items[0].status.availableReplicas} shell={.items[1].status.availableReplicas}{"\n"}' 2>&1 | grep -av memcache
echo "=== C) external app: 5 rapid probes to see if 504/000 is INTERMITTENT vs constant ==="
LB=130.214.18.166; H=testai.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu
kubectl -n platform-mesh-system run probe-fixed --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet -- sh -c '
for i in 1 2 3 4 5; do
  curl -sk -o /dev/null -w "  probe$i: http=%{http_code} time=%{time_total}s\n" --resolve '"$H"':443:'"$LB"' https://'"$H"'/ ;
  sleep 2;
done' 2>&1 | grep -av memcache | grep -E 'probe|http'
