#!/usr/bin/env bash
# Automated reproduction of the "deleted Application stays in the resource tree" behaviour.
#
# Each attempt: re-enable the tenant and wait for all package apps to be healthy, start refresh load,
# disable the tenant while the load is running (the blueprint AppSet deletes every package app),
# then check whether any deleted app is still in demo-blueprint's resource tree. If one is, hold
# WITHOUT intervening for HOLD_MINUTES to see whether it clears by itself, then try the remedies
# in order (normal refresh, hard refresh, in-cluster cache invalidation) and record which one works.
#
# Usage: tools/hold-test.sh [attempts=3]
#   env: HOLD_MINUTES (default 15), LOAD_RPS (default 8), PACKAGE_COUNT (default 26)
# Output: ./hold-test-<UTC timestamp>/ with events.log (timeline) and observe.log (observe.sh output).
# Summarise afterwards with: python3 tools/stale_report.py <dir>/observe.log <dir>/events.log
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/common.sh"
set +e
ATTEMPTS="${1:-3}"; HOLD_MINUTES="${HOLD_MINUTES:-15}"; LOAD_RPS="${LOAD_RPS:-8}"; PACKAGE_COUNT="${PACKAGE_COUNT:-26}"
OUT="$PWD/hold-test-$(date -u +%Y%m%dT%H%M%SZ)"; mkdir -p "$OUT"
LOG="$OUT/events.log"; : > "$LOG"
ev() { echo "$(date -u +%H:%M:%S) $*" | tee -a "$LOG"; }

real() { api "applications?projects=demo" | jq -r '[.items[]?.metadata.name | select(startswith("demo-package-"))] | sort | join(" ")'; }
tree() { api "applications/demo-blueprint/resource-tree?appNamespace=argocd" | jq -r '[.nodes[]? | select(.kind=="Application") | .name] | join(" ")'; }
stale() { local r out=""; r=" $(real) "; for n in $(tree); do [[ "$r" == *" $n "* ]] || out="$out $n"; done; echo "${out# }"; }
healthy_count() { api "applications?projects=demo" | jq '[.items[]? | select(.metadata.name|startswith("demo-package-"))
  | select(.status.sync.status=="Synced" and .status.health.status=="Healthy" and (.metadata.deletionTimestamp|not))] | length'; }
refresh() { api "applications/demo-blueprint?refresh=$1&appNamespace=argocd" >/dev/null; }
invalidate_in_cluster() { curl -s --max-time 30 -o /dev/null -w "%{http_code}" -X POST -H "Content-Type: application/json" -d '{}' \
  -H "Authorization: Bearer $ARGOCD_AUTH_TOKEN" "https://$ARGOCD_SERVER/api/v1/clusters/https%3A%2F%2Fkubernetes.default.svc/invalidate-cache"; }
check() { local s; s="$(stale)"; ev "  $1 -> stale: [${s:-none}]"; [ -n "$s" ]; }

"$ROOT/scripts/observe.sh" 5 > "$OUT/observe.log" 2>&1 & OBS=$!
trap 'kill $OBS 2>/dev/null' EXIT

for attempt in $(seq 1 "$ATTEMPTS"); do
  ev "=== attempt $attempt: re-enable"
  "$ROOT/scripts/flip.sh" false >/dev/null
  for _ in $(seq 1 60); do [ "$(healthy_count)" = "$PACKAGE_COUNT" ] && [ -z "$(stale)" ] && break; sleep 5; done
  ev "  healthy package apps: $(healthy_count)/$PACKAGE_COUNT"
  sleep 20
  "$ROOT/scripts/load.sh" 75 "$LOAD_RPS" > "$OUT/load-$attempt.log" 2>&1 & LOAD=$!
  sleep 45; ev "  flip true (load running)"; "$ROOT/scripts/flip.sh" true >/dev/null
  wait $LOAD; ev "  load stopped"
  sleep 60
  check "60s after delete" || { ev "  nothing stale - retrying"; continue; }

  cleared=""
  for i in $(seq 1 $(( HOLD_MINUTES * 2 ))); do
    sleep 30
    check "hold +$((i*30))s (no intervention)" || { cleared=$((i*30)); break; }
  done
  if [ -n "$cleared" ]; then ev "RESULT: reproduced; cleared by itself after ~$((cleared+60))s"; break; fi

  refresh normal; sleep 30; check "after normal refresh" || { ev "RESULT: reproduced; cleared by normal refresh"; break; }
  refresh hard;   sleep 30; check "after hard refresh"   || { ev "RESULT: reproduced; cleared by hard refresh"; break; }
  ev "  invalidate in-cluster cache: HTTP $(invalidate_in_cluster)"
  for i in 1 2 3 4 5 6; do
    sleep 30
    check "+$((i*30))s after in-cluster invalidate" || { ev "RESULT: reproduced; cleared ~$((i*30))s after in-cluster invalidate"; break 2; }
  done
  refresh normal; sleep 30
  check "after invalidate + refresh" && ev "RESULT: reproduced; still stale after all remedies" \
    || ev "RESULT: reproduced; cleared by in-cluster invalidate + refresh"
  break
done
ev "=== done (demo left disabled; scripts/flip.sh false to restore). Output: $OUT"
