#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
PGPOD=$(kubectl -n "$NS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep -E '^postgres' | awk '{print $1}' | head -1)
run(){ kubectl -n "$NS" exec "$PGPOD" -- sh -lc "PGPASSWORD=\$POSTGRES_PASSWORD psql -U \$POSTGRES_USER -d \$POSTGRES_DB -tA -c \"$1\"" 2>&1 | grep -avi memcache; }
echo "=== databases on this postgres ==="
run "SELECT datname FROM pg_database WHERE datistemplate=false ORDER BY 1;"
echo "=== row counts per table + tenant breakdown (ai_trust db) ==="
for t in ai_systems assessments obligations controls evidence evidence_versions alert_rules service_model_baselines custom_roles frameworks model_cards; do
  total=$(run "SELECT count(*) FROM $t;" 2>/dev/null)
  # tenant split only for tables with tenant_id
  has=$(run "SELECT 1 FROM information_schema.columns WHERE table_name='$t' AND column_name='tenant_id' LIMIT 1;" 2>/dev/null)
  if [ "$has" = "1" ]; then
    split=$(run "SELECT COALESCE(tenant_id,'<shared/NULL>')||'='||count(*) FROM $t GROUP BY tenant_id ORDER BY 1;" 2>/dev/null | tr '\n' ' ')
    printf "  %-26s total=%-5s [%s]\n" "$t" "$total" "$split"
  else
    printf "  %-26s total=%-5s (GLOBAL, no tenant_id)\n" "$t" "$total"
  fi
done
echo "=== alert_rules: are the seeded default rules present? (names) ==="
run "SELECT name FROM alert_rules ORDER BY 1;" 2>/dev/null | head -20
echo "=== frameworks (catalog) ==="
run "SELECT id||':'||name FROM frameworks ORDER BY 1;" 2>/dev/null | head
echo DONE
