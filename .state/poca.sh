#!/bin/bash
exec > /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP/.state/poca.out 2>&1
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
rm -f "$SHOOT_KUBECONFIG"; mint_shoot_kubeconfig || { echo LOGIN_EXPIRED; exit 3; }
export KUBECONFIG="$SHOOT_KUBECONFIG"
SUF="ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu"
LB=130.214.18.166; GWNS=platform-mesh-system
H="wzw3g7znvmqdk5qf-pocaitrust.$SUF"

echo "############ 1. all AITrust instances (find pocaitrust / wzw3g7znvmqdk5qf) ############"
kubectl get aitrustplatforminstances.trust.aitrust.msp -A 2>&1 | grep -avi memcache

echo
echo "############ 2. the namespace + pods for this instance ############"
NS="aitp-wzw3g7znvmqdk5qf-pocaitrust"
kubectl get ns "$NS" 2>&1 | grep -avi memcache
kubectl -n "$NS" get pods 2>&1 | grep -avi memcache | grep -vE 'Running|Completed' | head; echo "  ^ not-running (empty=all ok)"
echo "  total pods: $(kubectl -n "$NS" get pods --no-headers 2>&1 | grep -avi memcache | wc -l)"

echo
echo "############ 3. HTTPRoutes for this host (does the operator wire it?) ############"
kubectl -n "$GWNS" get httproute 2>&1 | grep -avi memcache | grep -E 'NAME|wzw3g7znvmqdk5qf|pocaitrust' | head

echo
echo "############ 4. DNS + served cert + HTTP response for the host ############"
kubectl -n "$GWNS" run r-$RANDOM --rm -i --restart=Never --image=alpine/openssl --quiet --command -- \
  sh -c "echo | openssl s_client -connect $LB:443 -servername $H 2>/dev/null | openssl x509 -noout -issuer -subject 2>/dev/null" 2>&1 | grep -avi memcache | grep -iE 'issuer|subject'
kubectl -n "$GWNS" run c-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet --command -- \
  sh -c "curl -sS --resolve $H:443:$LB https://$H/ -o /dev/null -w 'http=%{http_code} tls_ok\n' 2>&1 || curl -skS --resolve $H:443:$LB https://$H/ -o /dev/null -w 'http=%{http_code} (only with -k)\n' 2>&1" 2>&1 | grep -avi memcache | grep -E 'http=|curl|SSL|resolve'

echo
echo "############ 5. does the instance CR have status.url = this host? ############"
setup_kcp >/dev/null 2>&1; kcp_portforward >/dev/null 2>&1
for i in $(seq 1 15); do kc root get workspace >/dev/null 2>&1 && break; sleep 2; done
kubectl -n wzw3g7znvmqdk5qf get aitrustplatforminstances.trust.aitrust.msp 2>&1 | grep -avi memcache | head
echo DONE
