#!/bin/bash
# p4fix.sh — clean up the env-conflict + run openfga-provision + wire store id + roll backends to git images.
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
OFGA="http://openfga.platform-mesh-system.svc.cluster.local:8080"
ADMIN="$(kubectl -n "$NS" get secret app-secrets -o jsonpath='{.data.APP_ADMIN_USERNAME}' 2>/dev/null | base64 -d || echo admin)"

echo "=== 1) run openfga-provision → create store ai-trust-mt in the MESH OpenFGA + seed the 6 roles ==="
kubectl -n "$NS" delete job openfga-provision --ignore-not-found >/dev/null 2>&1
cat <<EOF | kubectl -n "$NS" apply -f - 2>&1 | grep -avi memcache
apiVersion: batch/v1
kind: Job
metadata: { name: openfga-provision, namespace: $NS }
spec:
  backoffLimit: 6
  template:
    metadata: { labels: { app: openfga-provision } }
    spec:
      restartPolicy: OnFailure
      nodeSelector: { workload: ai-trust-mt }
      tolerations: [{ key: workload, value: ai-trust-mt, effect: NoSchedule }]
      containers:
        - name: openfga-provision
          image: mirceacraciun795/aitrust-openfga-provision:aitrust-mt
          imagePullPolicy: Always
          env:
            - { name: OPENFGA_URL, value: "$OFGA" }
            - { name: OPENFGA_STORE_NAME, value: "ai-trust-mt" }
            - { name: INITIAL_ADMIN_USER, value: "$ADMIN" }
            - { name: OPENFGA_STORE_ID_FILE, value: "/tmp/store_id" }
EOF
kubectl -n "$NS" wait --for=condition=complete job/openfga-provision --timeout=180s 2>&1 | grep -avi memcache || {
  echo "-- provision not complete; logs: --"
  PP=$(kubectl -n "$NS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep openfga-provision | awk '{print $1}' | head -1)
  kubectl -n "$NS" logs "$PP" --tail=25 2>&1 | grep -avi memcache | tail -25
}
echo "=== 2) resolve the ai-trust-mt store id ==="
STORE_ID="$(kubectl -n "$NS" run sid-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet --command -- \
  sh -c "curl -s $OFGA/stores" 2>/dev/null | grep -oE '\{[^{}]*"name":"ai-trust-mt"[^{}]*\}' | grep -oE '"id":"[^"]+"' | head -1 | sed 's/.*"id":"//;s/"//')"
echo "STORE_ID=$STORE_ID"
[ -z "$STORE_ID" ] && { echo "NO STORE ID — abort env wiring"; exit 1; }

echo "=== 3) fix the env conflict: delete+reapply the 6 backends clean from the manifest, then set env once ==="
# re-render 30.yaml exactly as 3b does (ns + url + image rewrite), then delete+apply the 6 backends clean.
URL="https://ai-trust-mt.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu"
OUT=$(mktemp); sed -e "s|ai-trust-app|$NS|g" -e "s|__APP_URL__|$URL|g" -e "s|__OPENFGA_STORE_ID__|$STORE_ID|g" \
  -e "s|image: aitrust/\([a-z0-9-]*\):kind|image: mirceacraciun795/aitrust-\1:aitrust-mt|g" config/k8s-app/30-app.yaml > "$OUT"
for d in ai-system-registry-backend monitoring-backend overview-backend alerts-backend compliance-backend decision-trace-analyzer-backend users-backend; do
  kubectl -n "$NS" delete deploy "$d" --ignore-not-found >/dev/null 2>&1
done
kubectl -n "$NS" apply -f "$OUT" 2>&1 | grep -avi memcache | grep -iE 'backend|error' | head
rm -f "$OUT"
# runtime backends use the RLS app role; set it + ensure pull Always so git images land
APPDB="$(kubectl -n "$NS" get secret app-secrets -o jsonpath='{.data.APP_DATABASE_URL}' | base64 -d)"
for d in $(kubectl -n "$NS" get deploy -o name | grep -avi memcache | grep -E 'backend'); do
  kubectl -n "$NS" set env "$d" DATABASE_URL="$APPDB" >/dev/null 2>&1 || true
  kubectl -n "$NS" patch "$d" -p '{"spec":{"template":{"spec":{"containers":[{"name":"'"$(basename $d)"'","imagePullPolicy":"Always"}]}}}}' >/dev/null 2>&1 || true
  kubectl -n "$NS" patch "$d" --type=strategic -p '{"spec":{"template":{"spec":{"nodeSelector":{"workload":"ai-trust-mt"},"tolerations":[{"key":"workload","value":"ai-trust-mt","effect":"NoSchedule"}]}}}}' >/dev/null 2>&1 || true
done
echo "=== 4) settle + report ==="
sleep 20
kubectl -n "$NS" get deploy 2>&1 | grep -avi memcache | grep -E 'backend|NAME'
echo DONE
