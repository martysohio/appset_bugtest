#!/usr/bin/env bash
# Flap the switch repeatedly so deletions and recreations overlap (a tenant disabled and
# re-enabled while deletes are still being retried).
# Run scripts/observe.sh in another terminal and watch for STALE / stuck rows.
# Usage: scripts/storm.sh [cycles=10] [seconds-between-flips=8]
source "$(dirname "$0")/common.sh"
CYCLES="${1:-10}"; GAP="${2:-8}"
for i in $(seq 1 "$CYCLES"); do
  "$DEMO_DIR/scripts/flip.sh" true;  sleep "$GAP"
  "$DEMO_DIR/scripts/flip.sh" false; sleep "$GAP"
done
echo "storm done - leave observe.sh running a few minutes to see whether anything stays stale"
