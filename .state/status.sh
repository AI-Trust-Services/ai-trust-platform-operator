#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
echo "############ IS THE DEPLOY FINE? — component-by-component ############"
echo "=== 1. new worker pool ai-trust-mt ==="
kubectl get nodes -l worker.gardener.cloud/pool=ai-trust-mt 2>&1 | grep -avi memcache | grep -E 'NAME|Ready' | head
echo "=== 2. shared app pods (how many Running vs not) ==="
run=$(kubectl -n "$NS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep -c Running)
tot=$(kubectl -n "$NS" get pods --no-headers 2>/dev/null | grep -avi memcache | wc -l)
echo "  Running: $run / $tot"
echo "  not-Running/Completed:"; kubectl -n "$NS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep -vE 'Running|Completed' | head
echo "=== 3. provider APIExport publishes subscriptions? ==="
setup_kcp >/dev/null 2>&1; kcp_portforward >/dev/null 2>&1
for i in $(seq 1 12); do kc root get workspace >/dev/null 2>&1 && break; sleep 2; done
kc "$PROVIDER_WS" get apiexport "$EXPORT_NAME" -o jsonpath='apiexport={.metadata.name} resources={.status.resourceSchemas}{"\n"}' 2>&1 | grep -avi memcache | head -1 || echo "  (check)"
echo "=== 4. Subscription CR mirror + status ==="
kubectl get subscriptions.sub.aitrustmt.msp -A -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name} ready={.status.ready} phase={.status.phase} realm={.status.realm}{"\n"}{end}' 2>&1 | grep -avi memcache
echo "=== 5. portal content served (200)? ==="
kubectl -n "$NS" exec deploy/aitrust-mt-portal-integration -- sh -c 'wget -qO- -S http://localhost/pm-content.json 2>&1 | head -1' 2>&1 | grep -avi memcache | head -1 || echo "  (portal check)"
echo "=== 6. shared app reachable externally (oauth sign-in gate = healthy)? ==="
LB=130.214.18.166; H="$SHARED_APP_HOST"
kubectl -n "$NS" run e-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet --command -- \
  sh -c "curl -sk -o /dev/null -w 'shared app https://host/: http=%{http_code}\n' --resolve $H:443:$LB https://$H/" 2>&1 | grep -avi memcache | grep http=
echo DONE
