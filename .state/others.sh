#!/bin/bash
exec > /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP/.state/others.out 2>&1
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
[ -s "$SHOOT_KUBECONFIG" ] || mint_shoot_kubeconfig || { echo LOGIN_EXPIRED; exit 3; }

echo "=== roll shell for the OTHER existing instances (d, my-aitrust) — testai already done ==="
for NS in $(kubectl get ns -o name 2>/dev/null | grep -oE 'aitp-[a-z0-9-]+' | grep -v testai); do
  kubectl -n "$NS" get deploy shell >/dev/null 2>&1 || continue
  echo "-- $NS --"
  kubectl -n "$NS" patch deploy shell --type=json \
    -p '[{"op":"replace","path":"/spec/template/spec/containers/0/imagePullPolicy","value":"Always"}]' 2>&1 | grep -av memcache
  kubectl -n "$NS" rollout restart deploy/shell 2>&1 | grep -av memcache
done
for NS in $(kubectl get ns -o name 2>/dev/null | grep -oE 'aitp-[a-z0-9-]+' | grep -v testai); do
  kubectl -n "$NS" get deploy shell >/dev/null 2>&1 || continue
  kubectl -n "$NS" rollout status deploy/shell --timeout=150s 2>&1 | grep -av memcache | tail -1
done
echo "=== verify served viewUrls relative in each ==="
for NS in $(kubectl get ns -o name 2>/dev/null | grep -oE 'aitp-[a-z0-9-]+' | grep -v testai); do
  kubectl -n "$NS" get deploy shell >/dev/null 2>&1 || continue
  echo "-- $NS --"
  kubectl -n "$NS" exec deploy/shell -- cat /usr/share/nginx/html/luigi-config.js 2>/dev/null | grep -E 'viewUrl' | head -2
done

echo
echo "=== SLOWNESS DIAGNOSIS ==="
echo "--- node pressure (msp-at-big pool) ---"
kubectl top nodes 2>&1 | grep -av memcache | grep -E 'NAME|msp-at-big' || echo "(metrics-server?)"
echo "--- per-instance shell/oauth2 restarts + top pods by mem in testai ---"
kubectl top pods -n aitp-33hins0iklcwfg45-testai 2>&1 | grep -av memcache | sort -k3 -h -r | head -8 || echo "(no metrics)"
echo "--- any pods NOT Running across instances ---"
for NS in $(kubectl get ns -o name 2>/dev/null | grep -oE 'aitp-[a-z0-9-]+'); do
  bad=$(kubectl -n "$NS" get pods --no-headers 2>/dev/null | grep -avE 'Running|Completed' | wc -l)
  echo "  $NS: not-running=$bad"
done
echo DONE
