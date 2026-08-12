#!/bin/bash
exec > /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP/.state/step3-swap.out 2>&1
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
[ -s "$SHOOT_KUBECONFIG" ] || mint_shoot_kubeconfig || { echo LOGIN_EXPIRED; exit 3; }
GWNS=platform-mesh-system

echo "############ PRE-SWAP SAFETY: does any gateway listener need the 2-label host kcp.api.ai-trust-1 ? ############"
kubectl -n "$GWNS" get gateway k8sapi-gateway -o jsonpath='{range .spec.listeners[*]}{.name}{" host="}{.hostname}{"\n"}{end}' 2>&1 | grep -avi memcache
echo "  ^ LE SAN = apex + *.ai-trust-1 + *.services.ai-trust-1. 'kcp.api.ai-trust-1' (2 labels) NOT covered."
echo "  ^ If NO listener hostname is exactly/So needs kcp.api, the public gateway swap is safe (kcp.api is reached in-cluster via hostAlias, not this served cert)."

echo
echo "############ SWAP: overwrite domain-certificate secret data with cert-aitrust-full (LE) ############"
kubectl -n "$GWNS" get secret cert-aitrust-full -o jsonpath='{.data.tls\.crt}' 2>/dev/null | base64 -d > /tmp/le.crt
kubectl -n "$GWNS" get secret cert-aitrust-full -o jsonpath='{.data.tls\.key}' 2>/dev/null | base64 -d > /tmp/le.key
echo "  LE material sizes: crt=$(wc -c < /tmp/le.crt) key=$(wc -c < /tmp/le.key)"
kubectl -n "$GWNS" create secret tls domain-certificate --cert=/tmp/le.crt --key=/tmp/le.key \
  --dry-run=client -o yaml 2>/dev/null | grep -avi memcache | kubectl -n "$GWNS" apply -f - 2>&1 | grep -avi memcache

echo
echo "############ roll traefik so it reloads the served cert (pool-global) ############"
kubectl -n default rollout restart deploy/traefik 2>&1 | grep -avi memcache
kubectl -n default rollout status  deploy/traefik --timeout=150s 2>&1 | grep -avi memcache | tail -1

echo
echo "############ confirm domain-certificate secret is now LE ############"
kubectl -n "$GWNS" get secret domain-certificate -o jsonpath='{.data.tls\.crt}' 2>/dev/null | base64 -d 2>/dev/null | openssl x509 -noout -issuer -subject 2>&1 | grep -avi memcache
echo STEP3_DONE
