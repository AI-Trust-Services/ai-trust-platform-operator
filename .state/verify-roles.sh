#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
OFGA="http://openfga.platform-mesh-system.svc.cluster.local:8080"
SID=01KZX8TV6TMMF3G3F9DTE87YV4
echo "=== A) the authorization model in store ai-trust-mt (types user/role/platform + can_* relations) ==="
kubectl -n "$NS" run m-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet --command -- \
  sh -c "curl -s $OFGA/stores/$SID/authorization-models" 2>/dev/null | grep -avi memcache | tr ',' '\n' | grep -oE 'can_[a-z_]+|"type":"[a-z]+"|platform' | sort -u | head -30
echo
echo "=== B) role→permission tuples seeded? (read tuples: expect role:<name>#member -> can_* -> platform:global) ==="
kubectl -n "$NS" run t-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet --command -- \
  sh -c "curl -s -X POST $OFGA/stores/$SID/read -H 'content-type: application/json' -d '{}'" 2>/dev/null | grep -avi memcache | grep -oE 'role:[a-z_]+|can_[a-z_]+|platform:global|user:[a-z@._-]+' | sort | uniq -c | head -40
echo
echo "=== C) FUNCTIONAL CHECK: does platform_administrator get can_manage_iam on platform:global? ==="
# check the admin user (seeded as platform_administrator) -> can_manage_iam
ADMIN="$(kubectl -n "$NS" get secret app-secrets -o jsonpath='{.data.APP_ADMIN_USERNAME}' | base64 -d)"
kubectl -n "$NS" run c1-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet --command -- \
  sh -c "curl -s -X POST $OFGA/stores/$SID/check -H 'content-type: application/json' -d '{\"tuple_key\":{\"user\":\"user:$ADMIN\",\"relation\":\"can_manage_iam\",\"object\":\"platform:global\"}}'" 2>/dev/null | grep -avi memcache
echo "  ^ expect {\"allowed\":true} for admin=$ADMIN (seeded platform_administrator)"
echo "=== D) NEGATIVE: an auditor should NOT have can_manage_iam (role tuple check) ==="
kubectl -n "$NS" run c2-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet --command -- \
  sh -c "curl -s -X POST $OFGA/stores/$SID/check -H 'content-type: application/json' -d '{\"tuple_key\":{\"user\":\"role:auditor#member\",\"relation\":\"can_manage_iam\",\"object\":\"platform:global\"}}'" 2>/dev/null | grep -avi memcache
echo "  ^ expect {\"allowed\":false} (auditor lacks iam:manage)"
echo "=== E) auditor SHOULD have can_read_systems ==="
kubectl -n "$NS" run c3-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet --command -- \
  sh -c "curl -s -X POST $OFGA/stores/$SID/check -H 'content-type: application/json' -d '{\"tuple_key\":{\"user\":\"role:auditor#member\",\"relation\":\"can_read_systems\",\"object\":\"platform:global\"}}'" 2>/dev/null | grep -avi memcache
echo "  ^ expect {\"allowed\":true}"
echo DONE
